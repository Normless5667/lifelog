import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database.dart';
import '../db/repo.dart';
import '../debug/debug_server.dart';
import '../utils/date_utils.dart';
import 'battery_probe_service.dart';
import 'reminder_service.dart';

/// 本地使用数据埋点与导出分析服务（v1.8）：
/// - 严格本地存储（usage_events 表），绝不联网上报、不采集个人隐私内容（如食物名/体重数值/聊天内容）、不引入第三方 SDK
/// - 采集四类事件：
///   1) page：页面进入/离开/停留时长 (duration_ms) + 来源 (tab/push)
///   2) feature：功能 tap / success / fail / cancel + 耗时，用于计算功能转化率
///   3) perf：帧卡顿 (frame_jank > 16ms)、内存 (memory 每5分钟)、GPS 调用 (gps_call)、计时器活跃时段 (timer_tick)
///   4) lifecycle：前后台切换 (resumed / paused / detached)，用于统计日均使用时长
/// - 批量写入策略：内存缓冲，每 30 秒或满 50 条批量事务写入一次；切入后台立即 flush 并停止后台定时器（零后台耗电）
/// - 自动清理超过 30 天的历史记录
class UsageTelemetryService with WidgetsBindingObserver {
  UsageTelemetryService._();
  static final UsageTelemetryService instance = UsageTelemetryService._();

  static const appVersion = '3.4.0';
  static const _enabledKvKey = 'usage_telemetry_enabled';
  static const _flushIntervalSec = 30;
  static const _flushBatchThreshold = 50;
  static const _retentionDays = 30;

  final List<Map<String, Object?>> _buffer = [];
  bool _initialized = false;
  bool _enabled = true;
  bool _flushing = false;
  bool _inForeground = true;

  String _sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
  int _sessionResumeMs = DateTime.now().millisecondsSinceEpoch;

  String _currentPage = 'home';
  String _currentPageSource = 'tab';
  int _pageEnterMs = DateTime.now().millisecondsSinceEpoch;

  Timer? _flushTimer;
  Timer? _memoryTimer;

  // 帧卡顿节流聚合（防止高频掉帧把缓冲区打满）
  int _lastJankRecordMs = 0;
  int _accumulatedJankFrames = 0;
  double _maxJankFrameMs = 0;

  bool get isEnabled => _enabled;
  String get currentPage => _currentPage;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final saved = await Repo.getKv(_enabledKvKey);
    _enabled = (saved ?? '1') == '1';

    WidgetsBinding.instance.addObserver(this);
    _registerFrameTimingsCallback();
    _startForegroundTimers();
    await _pruneExpiredEvents();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _sessionId = 'sess_$nowMs';
    _sessionResumeMs = nowMs;
    _pageEnterMs = nowMs;
    _enqueue(
      category: 'lifecycle',
      name: 'resumed',
      action: 'ColdStart',
    );
    _sampleMemory();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await Repo.setKvSilent(_enabledKvKey, v ? '1' : '0');
    if (!v) {
      _buffer.clear();
    }
  }

  void _startForegroundTimers() {
    _flushTimer ??= Timer.periodic(const Duration(seconds: _flushIntervalSec), (_) {
      if (_inForeground && _buffer.isNotEmpty) {
        flush();
      }
    });
    _memoryTimer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      if (_inForeground && _enabled) {
        _sampleMemory();
      }
    });
  }

  void _stopForegroundTimers() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _memoryTimer?.cancel();
    _memoryTimer = null;
  }

  void _registerFrameTimingsCallback() {
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      if (!_enabled || !_inForeground) return;
      for (final t in timings) {
        final totalMs = t.totalSpan.inMicroseconds / 1000.0;
        if (totalMs > 16.5) {
          _accumulatedJankFrames++;
          if (totalMs > _maxJankFrameMs) {
            _maxJankFrameMs = totalMs;
          }
        }
      }
      if (_accumulatedJankFrames > 0) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastJankRecordMs >= 3000) {
          _lastJankRecordMs = nowMs;
          final count = _accumulatedJankFrames;
          final maxMs = double.parse(_maxJankFrameMs.toStringAsFixed(1));
          _accumulatedJankFrames = 0;
          _maxJankFrameMs = 0;
          _enqueue(
            category: 'perf',
            name: 'frame_jank',
            value: count.toDouble(),
            extra: {
              'page': _currentPage,
              'jank_count': count,
              'max_frame_ms': maxMs,
            },
          );
        }
      }
    });
  }

  void _sampleMemory() {
    if (!_enabled) return;
    try {
      final rssMb = double.parse((ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1));
      _enqueue(
        category: 'perf',
        name: 'memory',
        value: rssMb,
        extra: {'page': _currentPage},
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_inForeground) {
        _inForeground = false;
        _closeCurrentPage(nowMs);
        final fgDur = (nowMs - _sessionResumeMs).clamp(0, 86400000);
        _enqueue(
          category: 'lifecycle',
          name: state == AppLifecycleState.detached ? 'detached' : 'paused',
          durationMs: fgDur,
        );
      }
      // 切后台立即停止所有采样定时器、释放无用图片缓存并将缓冲刷入 SQLite
      _stopForegroundTimers();
      try {
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
      flush();
    } else if (state == AppLifecycleState.resumed) {
      if (!_inForeground) {
        _inForeground = true;
        _sessionId = 'sess_$nowMs';
        _sessionResumeMs = nowMs;
        _pageEnterMs = nowMs;
        _enqueue(
          category: 'lifecycle',
          name: 'resumed',
        );
        _startForegroundTimers();
      }
    }
  }

  void _closeCurrentPage(int nowMs) {
    if (_pageEnterMs <= 0) return;
    final dur = (nowMs - _pageEnterMs).clamp(0, 86400000);
    if (dur >= 100) {
      _enqueue(
        category: 'page',
        name: _currentPage,
        action: 'view',
        durationMs: dur,
        extra: {'source': _currentPageSource},
      );
    }
    _pageEnterMs = 0;
  }

  /// 2.1 记录页面切换与上一个页面的停留时长
  void enterPage(String pageName, {String source = 'tab'}) {
    DebugServer.instance.logPage(pageName, source: source);
    if (!_enabled) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_currentPage == pageName && _pageEnterMs > 0) return;
    _closeCurrentPage(nowMs);
    _currentPage = pageName;
    _currentPageSource = source;
    _pageEnterMs = nowMs;
  }

  /// 2.2 记录功能点击与成功/失败转化 (action: 'tap' | 'success' | 'fail' | 'cancel')
  void trackFeature(
    String feature,
    String action, {
    int? durationMs,
    String? errorMsg,
  }) {
    DebugServer.instance.logFeature(
      feature,
      action,
      durationMs: durationMs,
      errorMsg: errorMsg,
    );
    if (!_enabled) return;
    _enqueue(
      category: 'feature',
      name: feature,
      action: action,
      durationMs: durationMs,
      extra: errorMsg != null && errorMsg.isNotEmpty
          ? {'error': errorMsg.length > 120 ? errorMsg.substring(0, 120) : errorMsg}
          : null,
    );
  }

  /// 2.3 记录后台系统自动任务（不混入用户 feature 转化率，如 step_sync）
  void trackSystem(
    String name,
    String action, {
    int? durationMs,
    Map<String, Object?>? extra,
  }) {
    if (!_enabled) return;
    _enqueue(
      category: 'system',
      name: name,
      action: action,
      durationMs: durationMs,
      extra: extra,
    );
  }

  /// 2.4 记录性能与耗电事件 (kind: 'gps_call' | 'timer_active_sec' | 'db_write')
  void trackPerf(
    String kind, {
    num value = 1,
    int? durationMs,
    Map<String, Object?>? extra,
  }) {
    if (!_enabled) return;
    _enqueue(
      category: 'perf',
      name: kind,
      durationMs: durationMs,
      value: value.toDouble(),
      extra: extra,
    );
  }

  void _enqueue({
    required String category,
    required String name,
    String? action,
    int? durationMs,
    double? value,
    Map<String, Object?>? extra,
  }) {
    if (!_enabled) return;
    _buffer.add({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'category': category,
      'name': name,
      'action': action,
      'duration_ms': durationMs,
      'value': value,
      'extra': extra != null ? jsonEncode(extra) : null,
      'app_version': appVersion,
      'session_id': _sessionId,
    });
    if (_buffer.length >= _flushBatchThreshold) {
      flush();
    }
  }

  /// 批量将内存缓冲区事件一次性事务写入 SQLite
  Future<void> flush() async {
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;
    final batchItems = List<Map<String, Object?>>.from(_buffer);
    _buffer.clear();
    try {
      final db = await AppDatabase.instance.db;
      final batch = db.batch();
      for (final row in batchItems) {
        batch.insert('usage_events', row);
      }
      await batch.commit(noResult: true);
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  Future<void> _pruneExpiredEvents() async {
    try {
      final cutoffMs = DateTime.now()
          .subtract(const Duration(days: _retentionDays))
          .millisecondsSinceEpoch;
      final db = await AppDatabase.instance.db;
      await db.delete('usage_events', where: 'ts < ?', whereArgs: [cutoffMs]);
    } catch (_) {}
  }

  /// 获取当前已记录的事件总数（含内存缓冲区）
  Future<int> getEventCount() async {
    try {
      final db = await AppDatabase.instance.db;
      final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM usage_events');
      final dbCount = ((rows.first['cnt'] ?? 0) as num).toInt();
      return dbCount + _buffer.length;
    } catch (_) {
      return _buffer.length;
    }
  }

  /// 清空全部使用数据
  Future<void> clearAll() async {
    _buffer.clear();
    try {
      final db = await AppDatabase.instance.db;
      await db.delete('usage_events');
    } catch (_) {}
  }

  /// 纯函数聚合事件列表，确保 summary 与 events 统计口径完全一致（同时供单元测试验证）
  static Map<String, dynamic> summarizeEvents(
    List<Map<String, Object?>> rows, {
    int extraLiveFgMs = 0,
    int extraLiveTimerSec = 0,
    String? liveTodayDate,
  }) {
    var totalFgMs = 0;
    final activeDaysSet = <String>{};
    final pageMsMap = <String, int>{};
    final pageViewsMap = <String, int>{};
    final featureCounts = <String, Map<String, int>>{};
    final systemCounts = <String, Map<String, int>>{};
    var jankFramesTotal = 0;
    var jankEventsTotal = 0;
    var maxJankMs = 0.0;
    var memorySumMb = 0.0;
    var memorySamples = 0;
    var gpsCallsTotal = 0;
    var timerActiveMsTotal = 0;

    for (final r in rows) {
      final ts = ((r['ts'] ?? 0) as num).toInt();
      if (ts > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        activeDaysSet.add(fmtDate(dt));
      }

      final cat = (r['category'] ?? '').toString();
      final name = (r['name'] ?? '').toString();
      final action = (r['action'] ?? '').toString();
      final durMs = ((r['duration_ms'] ?? 0) as num).toInt();
      final val = ((r['value'] ?? 0) as num).toDouble();
      Map<String, dynamic>? extraMap;
      final rawExtra = r['extra'] as String?;
      if (rawExtra != null && rawExtra.isNotEmpty) {
        try {
          extraMap = jsonDecode(rawExtra) as Map<String, dynamic>;
        } catch (_) {}
      }

      if (cat == 'lifecycle' && (name == 'paused' || name == 'detached')) {
        totalFgMs += durMs;
      } else if (cat == 'page') {
        pageMsMap[name] = (pageMsMap[name] ?? 0) + durMs;
        pageViewsMap[name] = (pageViewsMap[name] ?? 0) + 1;
      } else if (cat == 'feature') {
        // 兼容历史旧版写入的 step_sync，避免拉偏用户功能转化率
        if (name == 'step_sync') {
          final sb = systemCounts.putIfAbsent(name, () => {'success': 0, 'fail': 0});
          if (sb.containsKey(action)) sb[action] = (sb[action] ?? 0) + 1;
          continue;
        }
        final bucket = featureCounts.putIfAbsent(
          name,
          () => {'tap': 0, 'success': 0, 'fail': 0, 'cancel': 0},
        );
        if (bucket.containsKey(action)) {
          bucket[action] = (bucket[action] ?? 0) + 1;
        }
      } else if (cat == 'system') {
        final sb = systemCounts.putIfAbsent(name, () => {'success': 0, 'fail': 0});
        if (sb.containsKey(action)) {
          sb[action] = (sb[action] ?? 0) + 1;
        }
      } else if (cat == 'perf') {
        if (name == 'frame_jank') {
          jankEventsTotal++;
          final jc = ((extraMap?['jank_count'] ?? (val >= 1 ? val.round() : 1)) as num).toInt();
          jankFramesTotal += jc.clamp(1, 10000);
          final frameMs = ((extraMap?['max_frame_ms'] ?? 0) as num).toDouble();
          if (frameMs > maxJankMs) maxJankMs = frameMs;
        } else if (name == 'memory' && val > 0) {
          memorySumMb += val;
          memorySamples++;
        } else if (name == 'gps_call') {
          gpsCallsTotal += val.round().clamp(1, 100);
        } else if (name == 'timer_active_sec' || name == 'timer_tick') {
          timerActiveMsTotal += durMs > 0 ? durMs : (val * 1000).round();
        }
      }
    }

    if (extraLiveFgMs > 0) {
      totalFgMs += extraLiveFgMs;
      if (liveTodayDate != null) activeDaysSet.add(liveTodayDate);
    }

    final topPages = pageMsMap.entries.map((e) {
      return {
        'page': e.key,
        'minutes': double.parse((e.value / 60000.0).toStringAsFixed(1)),
        'views': pageViewsMap[e.key] ?? 1,
      };
    }).toList()
      ..sort((a, b) => ((b['minutes'] as num).compareTo(a['minutes'] as num)));

    final featureConversion = featureCounts.entries.map((e) {
      final tap = e.value['tap'] ?? 0;
      final success = e.value['success'] ?? 0;
      final fail = e.value['fail'] ?? 0;
      final cancel = e.value['cancel'] ?? 0;
      final denom = tap > 0 ? tap : (success + fail + cancel);
      final rate = denom > 0
          ? double.parse((success / denom).clamp(0.0, 1.0).toStringAsFixed(2))
          : 0.0;
      return {
        'feature': e.key,
        'tap': tap,
        'success': success,
        'fail': fail,
        'cancel': cancel,
        'rate': rate,
      };
    }).toList();

    return {
      'total_fg_minutes': (totalFgMs / 60000.0).round(),
      'daily_active_days': activeDaysSet.length,
      'total_events': rows.length,
      'top_pages': topPages,
      'feature_conversion': featureConversion,
      'system_tasks': systemCounts,
      'perf': {
        'jank_events': jankEventsTotal,
        'jank_frames': jankFramesTotal,
        'max_jank_ms': double.parse(maxJankMs.toStringAsFixed(1)),
        'avg_memory_mb': memorySamples > 0
            ? double.parse((memorySumMb / memorySamples).toStringAsFixed(1))
            : 0.0,
        'gps_calls': gpsCallsTotal,
        'timer_active_seconds': (timerActiveMsTotal / 1000).round() + extraLiveTimerSec,
      },
    };
  }

  /// 查询指定天数范围内的事件并构建带 summary 的完整分析数据包
  Future<Map<String, dynamic>> buildExportPayload({int? days}) async {
    await flush();
    final now = DateTime.now();
    final fromDt = days != null ? now.subtract(Duration(days: days)) : DateTime(2025, 1, 1);
    final fromMs = fromDt.millisecondsSinceEpoch;

    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'usage_events',
      where: days != null ? 'ts >= ?' : null,
      whereArgs: days != null ? [fromMs] : null,
      orderBy: 'ts DESC',
    );

    final liveFgMs = (_inForeground && _sessionResumeMs > 0)
        ? (now.millisecondsSinceEpoch - _sessionResumeMs).clamp(0, 86400000)
        : 0;
    final summary = summarizeEvents(
      rows,
      extraLiveFgMs: liveFgMs,
      extraLiveTimerSec: BatteryProbeService.instance.currentActiveTimerSeconds,
      liveTodayDate: today(),
    );

    final notifStatus = await ReminderService.checkNotificationStatus();
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    final screenStr = view != null
        ? '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}'
        : 'unknown';

    return {
      'exported_at': now.toIso8601String(),
      'app_version': appVersion,
      'device': {
        'model': notifStatus.device,
        'os': Platform.operatingSystem,
        'screen': screenStr,
      },
      'range': {
        'from': days != null ? fmtDate(fromDt) : 'all',
        'to': fmtDate(now),
        'days': days ?? 'all',
      },
      'summary': summary,
      'events': rows,
    };
  }

  /// 导出并分享使用数据（支持 'json' 或 'csv'，范围 days: 1 / 7 / 30 / null）
  Future<void> exportAndShare({required String format, int? days}) async {
    final payload = await buildExportPayload(days: days);
    final dir = await getTemporaryDirectory();
    final rangeTag = days != null ? '${days}d' : 'all';

    if (format == 'csv') {
      final buf = StringBuffer();
      buf.writeln('ts,iso_time,category,name,action,duration_ms,value,session_id,extra');
      final events = (payload['events'] as List?) ?? const [];
      for (final raw in events.whereType<Map>()) {
        final ts = ((raw['ts'] ?? 0) as num).toInt();
        final iso = DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String();
        final extraStr = (raw['extra'] ?? '').toString().replaceAll('"', '""');
        buf.writeln(
          '$ts,$iso,${raw['category'] ?? ''},${raw['name'] ?? ''},${raw['action'] ?? ''},'
          '${raw['duration_ms'] ?? ''},${raw['value'] ?? ''},${raw['session_id'] ?? ''},"$extraStr"',
        );
      }
      final file = File('${dir.path}/lifelog_usage_${rangeTag}_${today()}.csv');
      await file.writeAsString('\uFEFF${buf.toString()}');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'LifeLog Usage Telemetry ($rangeTag CSV)',
        ),
      );
    } else {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final file = File('${dir.path}/lifelog_usage_${rangeTag}_${today()}.json');
      await file.writeAsString(jsonStr);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'LifeLog Usage Telemetry ($rangeTag JSON)',
        ),
      );
    }
  }
}
