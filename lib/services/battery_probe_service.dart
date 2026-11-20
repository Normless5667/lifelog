import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../db/repo.dart';
import '../utils/date_utils.dart';
import 'usage_telemetry_service.dart';

class DayBatteryMetrics {
  final String date;
  int foregroundSec;
  int backgroundSec;
  int timerActiveSec;
  int gpsCalls;
  int dbWrites;
  int widgetRefreshes;

  DayBatteryMetrics({
    required this.date,
    this.foregroundSec = 0,
    this.backgroundSec = 0,
    this.timerActiveSec = 0,
    this.gpsCalls = 0,
    this.dbWrites = 0,
    this.widgetRefreshes = 0,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'foregroundSec': foregroundSec,
        'backgroundSec': backgroundSec,
        'timerActiveSec': timerActiveSec,
        'gpsCalls': gpsCalls,
        'dbWrites': dbWrites,
        'widgetRefreshes': widgetRefreshes,
      };

  factory DayBatteryMetrics.fromJson(Map<String, dynamic> j) => DayBatteryMetrics(
        date: (j['date'] ?? today()).toString(),
        foregroundSec: ((j['foregroundSec'] ?? 0) as num).toInt(),
        backgroundSec: ((j['backgroundSec'] ?? 0) as num).toInt(),
        timerActiveSec: ((j['timerActiveSec'] ?? 0) as num).toInt(),
        gpsCalls: ((j['gpsCalls'] ?? 0) as num).toInt(),
        dbWrites: ((j['dbWrites'] ?? 0) as num).toInt(),
        widgetRefreshes: ((j['widgetRefreshes'] ?? 0) as num).toInt(),
      );
}

/// 耗电性能探针服务（滚动保留最近 7 天统计，内存中累加，节流刷入 kv 表避免探针自身产生高频写库）：
/// 统计项：
/// - 前台运行时长 (foregroundSec)
/// - 后台驻留时长 (backgroundSec)
/// - 计时器活跃时长 (timerActiveSec)
/// - GPS 定位调用次数 (gpsCalls)
/// - 数据库写入次数 (dbWrites)
/// - 桌面小组件刷新次数 (widgetRefreshes)
class BatteryProbeService with WidgetsBindingObserver {
  BatteryProbeService._();
  static final BatteryProbeService instance = BatteryProbeService._();

  static const _kvKey = 'battery_probe_7d_v1';
  final Map<String, DayBatteryMetrics> _days = {};
  bool _initialized = false;
  bool _flushing = false;
  int _lastFlushMs = 0;

  int _fgResumeAtMs = 0;
  int _bgPauseAtMs = 0;
  final Map<String, int> _activeTimerStartsMs = {};

  /// 全局 RouteObserver，供校车看板等页面监听 pushNext/popNext 自动暂停/恢复动画与计时器
  static final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _fgResumeAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final raw = await Repo.getKv(_kvKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List?) ?? const [];
        for (final item in list.whereType<Map>()) {
          final m = DayBatteryMetrics.fromJson(Map<String, dynamic>.from(item));
          _days[m.date] = m;
        }
        _pruneOldDays();
      }
    } catch (_) {}
  }

  DayBatteryMetrics _todayBucket() {
    final t = today();
    return _days.putIfAbsent(t, () {
      _pruneOldDays();
      return DayBatteryMetrics(date: t);
    });
  }

  void _pruneOldDays() {
    if (_days.length <= 7) return;
    final sortedKeys = _days.keys.toList()..sort();
    while (sortedKeys.length > 7) {
      final oldest = sortedKeys.removeAt(0);
      _days.remove(oldest);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final b = _todayBucket();
    // 仅在真正切后台 (paused/hidden/detached) 时结算，不在 inactive（下拉通知栏/手势边缘/来电）误停
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_fgResumeAtMs > 0) {
        final deltaSec = ((nowMs - _fgResumeAtMs) ~/ 1000).clamp(0, 86400);
        b.foregroundSec += deltaSec;
        _fgResumeAtMs = 0;
      }
      if (_bgPauseAtMs == 0) {
        _bgPauseAtMs = nowMs;
      }
      // 结算所有仍在活跃的计时器，并同步写入累计活跃秒数遥测，防止切后台前秒数丢失
      for (final key in _activeTimerStartsMs.keys.toList()) {
        final startMs = _activeTimerStartsMs[key]!;
        final durMs = (nowMs - startMs).clamp(0, 86400000);
        if (durMs >= 500) {
          b.timerActiveSec += (durMs ~/ 1000).clamp(0, 86400);
          UsageTelemetryService.instance.trackPerf(
            'timer_active_sec',
            durationMs: durMs,
            value: double.parse((durMs / 1000.0).toStringAsFixed(1)),
            extra: {'timer': key, 'reason': 'bg_settle'},
          );
        }
        _activeTimerStartsMs[key] = nowMs;
      }
      flush(force: true);
    } else if (state == AppLifecycleState.resumed) {
      if (_bgPauseAtMs > 0) {
        final deltaSec = ((nowMs - _bgPauseAtMs) ~/ 1000).clamp(0, 86400);
        b.backgroundSec += deltaSec;
        _bgPauseAtMs = 0;
      }
      _fgResumeAtMs = nowMs;
    }
  }

  void onTimerStarted(String tag) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _activeTimerStartsMs.putIfAbsent(tag, () => nowMs);
  }

  void onTimerStopped(String tag) {
    final startMs = _activeTimerStartsMs.remove(tag);
    if (startMs != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final durMs = (nowMs - startMs).clamp(0, 86400000);
      if (durMs >= 500) {
        _todayBucket().timerActiveSec += (durMs ~/ 1000).clamp(0, 86400);
        UsageTelemetryService.instance.trackPerf(
          'timer_active_sec',
          durationMs: durMs,
          value: double.parse((durMs / 1000.0).toStringAsFixed(1)),
          extra: {'timer': tag},
        );
      }
      _maybeFlush();
    }
  }

  /// 当前仍在运行中的计时器尚未结算的累计活跃秒数
  int get currentActiveTimerSeconds {
    if (_activeTimerStartsMs.isEmpty) return 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var totalSec = 0;
    for (final startMs in _activeTimerStartsMs.values) {
      totalSec += ((nowMs - startMs) ~/ 1000).clamp(0, 86400);
    }
    return totalSec;
  }

  void recordGpsCall() {
    _todayBucket().gpsCalls++;
    UsageTelemetryService.instance.trackPerf('gps_call', value: 1);
    _maybeFlush();
  }

  void recordDbWrite() {
    _todayBucket().dbWrites++;
  }

  void recordWidgetRefresh() {
    _todayBucket().widgetRefreshes++;
    _maybeFlush();
  }

  int get activeTimerCount => _activeTimerStartsMs.length;
  List<String> get activeTimerTags => _activeTimerStartsMs.keys.toList();

  void _maybeFlush() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastFlushMs >= 60 * 1000) {
      flush();
    }
  }

  /// 将内存统计刷入 kv 表（本身不计入 dbWrites，防止递归）
  Future<void> flush({bool force = false}) async {
    if (_flushing) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && nowMs - _lastFlushMs < 30 * 1000) return;
    _flushing = true;
    _lastFlushMs = nowMs;
    try {
      final b = _todayBucket();
      if (_fgResumeAtMs > 0) {
        b.foregroundSec += ((nowMs - _fgResumeAtMs) ~/ 1000).clamp(0, 86400);
        _fgResumeAtMs = nowMs;
      }
      for (final key in _activeTimerStartsMs.keys.toList()) {
        final startMs = _activeTimerStartsMs[key]!;
        b.timerActiveSec += ((nowMs - startMs) ~/ 1000).clamp(0, 86400);
        _activeTimerStartsMs[key] = nowMs;
      }
      _pruneOldDays();
      final list = (_days.values.toList()..sort((a, b) => b.date.compareTo(a.date)))
          .map((e) => e.toJson())
          .toList();
      await Repo.setKvSilent(_kvKey, jsonEncode(list));
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  /// 获取最近 7 天统计快照（含实时结算的今日数据）
  Future<List<DayBatteryMetrics>> getRolling7Days() async {
    await init();
    await flush(force: true);
    final list = _days.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) {
      return [ _todayBucket() ];
    }
    return list;
  }

  Future<void> resetStats() async {
    _days.clear();
    _fgResumeAtMs = DateTime.now().millisecondsSinceEpoch;
    _bgPauseAtMs = 0;
    await flush(force: true);
  }
}
