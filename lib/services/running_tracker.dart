import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/run_models.dart';
import '../utils/date_utils.dart';
import 'nutrition.dart';
import 'reminder_service.dart';
import 'run_course_engine.dart';
import 'run_voice_coach.dart';

/// Haversine 球面距离公式（单位：米）
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

double _degToRad(double deg) => deg * (math.pi / 180.0);

/// 格式化跑步时长：MM:SS 或 H:MM:SS
String formatRunDuration(int totalSecs) {
  final s = totalSecs < 0 ? 0 : totalSecs;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(sec)}';
  return '${two(m)}:${two(sec)}';
}

/// 格式化配速：6'12"（无效或不足距离返回 --'--"）
String formatRunPace(int? secsPerKm) {
  if (secsPerKm == null || secsPerKm < 120 || secsPerKm > 2400) {
    return "--'--\"";
  }
  final m = secsPerKm ~/ 60;
  final s = secsPerKm % 60;
  return "$m'${s.toString().padLeft(2, '0')}\"";
}

/// 根据真实距离、配速与体重估算跑步热量（直接复用 Nutrition.estimateRunKcal 唯一口径；无 GPS 距离时 MET 7.0 兜底）
int estimateRunCalories({
  required double distanceMeters,
  required double weightKg,
  required int activeDurationSecs,
}) {
  return Nutrition.estimateRunKcal(
    distanceKm: distanceMeters / 1000.0,
    weightKg: weightKg,
    durationSecs: activeDurationSecs,
  ).round();
}

/// 配速曲线采样点（距离 km -> 配速 分/公里）
class PaceCurveSample {
  final double km;
  final double paceMinPerKm;

  const PaceCurveSample({
    required this.km,
    required this.paceMinPerKm,
  });
}

/// 从轨迹点序列计算平滑配速曲线（供跑步详情页 fl_chart 渲染）。
/// 自动剔除暂停断档、瞬移跳点与极端配速，点数或距离不足时返回空列表。
List<PaceCurveSample> computePaceCurveSamples(List<RoutePoint> points) {
  if (points.length < 3) return const [];

  // 第一遍：统计有效推进总距离
  double totalDistM = 0;
  final validSteps = <({double distM, double dtSec})>[];
  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final cur = points[i];
    final dtSec = (cur.t - prev.t) / 1000.0;
    if (dtSec <= 0 || dtSec > 60.0) continue;
    final distM = haversineMeters(prev.lat, prev.lng, cur.lat, cur.lng);
    if (distM < 0.5) continue;
    final speedMps = distM / dtSec;
    if (speedMps > RunTrackProcessor.maxHumanSpeedMps || speedMps < 0.3) continue;
    validSteps.add((distM: distM, dtSec: dtSec));
    totalDistM += distM;
  }

  if (validSteps.length < 2 || totalDistM < 60.0) return const [];

  // 动态分桶：最多约 32 个平滑采样点，短距离（如 200m）也能出 4+ 个点
  final targetBucketM = math.max(35.0, math.min(250.0, totalDistM / 28.0));
  final raw = <PaceCurveSample>[];
  double cumM = 0;
  double bucketM = 0;
  double bucketSec = 0;

  for (final step in validSteps) {
    cumM += step.distM;
    bucketM += step.distM;
    bucketSec += step.dtSec;
    if (bucketM >= targetBucketM && bucketSec >= 2.0) {
      final pace = (bucketSec / 60.0) / (bucketM / 1000.0);
      if (pace >= 2.0 && pace <= 20.0) {
        raw.add(PaceCurveSample(
          km: double.parse((cumM / 1000.0).toStringAsFixed(3)),
          paceMinPerKm: pace,
        ));
      }
      bucketM = 0;
      bucketSec = 0;
    }
  }
  if (bucketM >= targetBucketM * 0.4 && bucketSec >= 2.0) {
    final pace = (bucketSec / 60.0) / (bucketM / 1000.0);
    if (pace >= 2.0 && pace <= 20.0) {
      raw.add(PaceCurveSample(
        km: double.parse((cumM / 1000.0).toStringAsFixed(3)),
        paceMinPerKm: pace,
      ));
    }
  }

  if (raw.length < 2) return const [];
  if (raw.length < 3) return raw;

  // 轻度 3 点加权平滑（0.25 / 0.50 / 0.25）消除局部 GPS 抖动
  final smoothed = <PaceCurveSample>[raw.first];
  for (var i = 1; i < raw.length - 1; i++) {
    final avgPace = 0.25 * raw[i - 1].paceMinPerKm +
        0.50 * raw[i].paceMinPerKm +
        0.25 * raw[i + 1].paceMinPerKm;
    smoothed.add(PaceCurveSample(km: raw[i].km, paceMinPerKm: avgPace));
  }
  smoothed.add(raw.last);
  return smoothed;
}

/// 纯 GPS 轨迹过滤、平滑与距离累计引擎（零平台依赖，便于单元测试验证误差 < 5%）
class RunTrackProcessor {
  static const double maxAccuracyMeters = 20.0;
  static const double maxHumanSpeedMps = 12.5; // ~45 km/h，拦截 GPS 瞬移跳点
  static const double maxShortJumpMeters = 80.0; // <= 2.5s 突跳 > 80m 视为漂移
  static const double minMoveMeters = 1.5; // 静止漂移抑制阈值
  static const double smoothingAlpha = 0.60; // EMA 坐标平滑系数

  final List<List<RoutePoint>> _segments = [];
  List<RoutePoint> _currentSegment = [];
  RoutePoint? _lastRawAccepted;
  double _distanceMeters = 0;
  int _droppedAccuracy = 0;
  int _droppedSpike = 0;

  double get distanceMeters => _distanceMeters;
  int get droppedAccuracyCount => _droppedAccuracy;
  int get droppedSpikeCount => _droppedSpike;

  List<List<RoutePoint>> get segments => List.unmodifiable(_segments);

  List<RoutePoint> get allPoints => [
        for (final seg in _segments) ...seg,
      ];

  RoutePoint? get latestPoint =>
      _currentSegment.isNotEmpty
          ? _currentSegment.last
          : (_segments.isNotEmpty && _segments.last.isNotEmpty ? _segments.last.last : null);

  /// 暂停时切断当前分段：恢复后的首个点作为新段起点，绝不把暂停期间的位移算入距离
  void markPauseBreak() {
    _currentSegment = [];
    _lastRawAccepted = null;
  }

  /// 跑步结束并释放控制器时主动清空轨迹点，避免长距离跑步点集滞留内存
  void reset() {
    _segments.clear();
    _currentSegment = [];
    _lastRawAccepted = null;
    _distanceMeters = 0;
  }

  /// 注入一个原始 GPS 点；返回 true 表示点有效并计入轨迹
  bool addRawPoint(RoutePoint raw, {required bool isPaused}) {
    if (isPaused) return false;
    if (!raw.lat.isFinite || !raw.lng.isFinite) return false;

    // 1) 过滤精度差的点（accuracy > 20m 直接丢弃）
    if (raw.accuracy != null && raw.accuracy! > maxAccuracyMeters) {
      _droppedAccuracy++;
      return false;
    }

    // 2) 新分段起点（开跑首点或暂停恢复后首点）：直接锚定，不累加跨段距离
    if (_currentSegment.isEmpty || _lastRawAccepted == null) {
      _currentSegment = [raw];
      _segments.add(_currentSegment);
      _lastRawAccepted = raw;
      return true;
    }

    final prevRaw = _lastRawAccepted!;
    final dtSec = (raw.t - prevRaw.t) / 1000.0;
    if (dtSec <= 0) return false;

    // 3) 过滤速度突变 / GPS 瞬移跳点
    final rawDist = haversineMeters(prevRaw.lat, prevRaw.lng, raw.lat, raw.lng);
    final speedMps = rawDist / dtSec;
    if (speedMps > maxHumanSpeedMps || (dtSec <= 2.5 && rawDist > maxShortJumpMeters)) {
      _droppedSpike++;
      return false;
    }

    // 4) 过滤原地微小漂移
    if (rawDist < minMoveMeters) {
      return false;
    }

    // 5) 轻量 EMA 坐标平滑，压制左右锯齿漂移同时保留真实前进距离
    final prevSmoothed = _currentSegment.last;
    final smoothedLat =
        prevSmoothed.lat + smoothingAlpha * (raw.lat - prevSmoothed.lat);
    final smoothedLng =
        prevSmoothed.lng + smoothingAlpha * (raw.lng - prevSmoothed.lng);
    final smoothed = RoutePoint(
      lat: smoothedLat,
      lng: smoothedLng,
      t: raw.t,
      accuracy: raw.accuracy,
    );

    final segDist = haversineMeters(
      prevSmoothed.lat,
      prevSmoothed.lng,
      smoothed.lat,
      smoothed.lng,
    );
    if (segDist < 0.5) return false;

    _distanceMeters += segDist;
    _currentSegment.add(smoothed);
    _lastRawAccepted = raw;
    return true;
  }
}

/// Android 原生跑步前台服务与定位权限状态桥接
class RunningNativeService {
  RunningNativeService._();

  static const _ch = MethodChannel('com.lifelog/running');

  static Future<bool> startForegroundService({
    required String title,
    required String body,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('startForegroundService', {
        'title': title,
        'body': body,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateForegroundNotification({
    required String title,
    required String body,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('updateForegroundNotification', {
        'title': title,
        'body': body,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopForegroundService() async {
    try {
      final ok = await _ch.invokeMethod<bool>('stopForegroundService');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<({bool fine, bool coarse, bool background, int sdkInt})>
      checkLocationPermissions() async {
    try {
      final res = await _ch.invokeMethod<Map>('checkLocationPermissions');
      if (res != null) {
        return (
          fine: (res['fine'] as bool?) ?? false,
          coarse: (res['coarse'] as bool?) ?? false,
          background: (res['background'] as bool?) ?? false,
          sdkInt: (res['sdkInt'] as int?) ?? 30,
        );
      }
    } catch (_) {}
    return (fine: false, coarse: false, background: false, sdkInt: 30);
  }

  static Future<bool> openAppSettings() async {
    try {
      final ok = await _ch.invokeMethod<bool>('openAppSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openTtsSettings() async {
    try {
      final ok = await _ch.invokeMethod<bool>('openTtsSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// 课程分段切换事件（供 UI 滑入横幅与测试验证）
class SegmentTransitionEvent {
  final int eventId;
  final RunningCourseSegment? segment;
  final int segmentNumber; // 1-based
  final int totalSegments;
  final bool courseCompleted;
  final bool forcedByTimeout;

  const SegmentTransitionEvent({
    required this.eventId,
    required this.segment,
    required this.segmentNumber,
    required this.totalSegments,
    this.courseCompleted = false,
    this.forcedByTimeout = false,
  });
}

/// 跑步会话实时控制器：
/// - 使用 Geolocator.getPositionStream(distanceFilter: 5) 省电追踪，绝不定时轮询
/// - 启动 Android 前台定位服务（常驻通知「正在记录跑步」）防止切后台断轨
/// - 使用单调真实时钟区分「运动时长（不含暂停）」与「总时长（含暂停）」
/// - 驱动 RunCourseEngine 按时间 / 按距离自动推进课程分段 + RunVoiceCoach 语音播报与震动
/// - 屏幕常亮（wakelock_plus）
class RunningTrackerController extends ChangeNotifier {
  final double weightKg;
  final double? targetDistanceKm;
  final RunningCourse? course;
  final String notificationTitle;
  final bool isEnglish;
  final void Function(String text)? onSpeakForTest;
  final bool simulateVoiceUnavailableForTest;

  final RunTrackProcessor _processor = RunTrackProcessor();
  final RunVoiceCoach voiceCoach;
  late final RunCourseEngine? courseEngine;

  StreamSubscription<Position>? _posSub;
  Timer? _uiTicker;

  bool _started = false;
  bool _paused = false;
  bool _finished = false;
  bool _targetNotified = false;
  bool _skipPlatformSideEffects = false;
  bool _voiceUnavailablePromptNeeded = false;

  DateTime? _startAt;
  DateTime? _pauseStartedAt;
  int _accumulatedPausedMs = 0;
  int? _activeSecsOverrideForTest;
  DateTime? _lastNotifSyncAt;
  double? _latestAccuracy;
  String? _gpsError;
  int _lastAnnouncedKm = 0;
  int _bannerSeq = 0;
  SegmentTransitionEvent? _latestBannerEvent;

  RunningTrackerController({
    required this.weightKg,
    this.targetDistanceKm,
    this.course,
    this.notificationTitle = '正在记录跑步',
    this.isEnglish = false,
    this.onSpeakForTest,
    this.simulateVoiceUnavailableForTest = false,
    RunVoiceCoach? voiceCoach,
  }) : voiceCoach = voiceCoach ?? RunVoiceCoach() {
    courseEngine = (course != null && course!.segments.isNotEmpty)
        ? RunCourseEngine(course!)
        : null;
  }

  bool get isStarted => _started;
  bool get isPaused => _paused;
  bool get isFinished => _finished;
  bool get targetReached => _targetNotified;
  bool get hasCourseSegments => courseEngine != null;
  bool get isCourseCompleted => courseEngine?.isCompleted ?? false;
  bool get isVoiceMuted => voiceCoach.isMuted;
  bool get isVoiceAvailable => voiceCoach.isAvailable;
  bool get voiceUnavailablePromptNeeded => _voiceUnavailablePromptNeeded;
  String? get voiceFailureReason => voiceCoach.lastFailureReason;
  SegmentTransitionEvent? get latestBannerEvent => _latestBannerEvent;

  void consumeVoiceUnavailablePrompt() {
    _voiceUnavailablePromptNeeded = false;
  }

  Future<bool> retryVoiceInit() async {
    final ok = await voiceCoach.retryInit(isEnglish: isEnglish);
    notifyListeners();
    return ok;
  }
  double? get latestAccuracy => _latestAccuracy;
  String? get gpsError => _gpsError;
  DateTime? get startAt => _startAt;

  double get distanceMeters => _processor.distanceMeters;
  double get distanceKm => _processor.distanceMeters / 1000.0;
  List<List<RoutePoint>> get trackSegments => _processor.segments;
  List<RoutePoint> get allPoints => _processor.allPoints;
  RoutePoint? get latestPoint => _processor.latestPoint;

  void toggleVoiceMute() {
    voiceCoach.setMuted(!voiceCoach.isMuted);
    notifyListeners();
  }

  /// 总时长（秒，含暂停）
  int get totalDurationSecs {
    if (_activeSecsOverrideForTest != null) return _activeSecsOverrideForTest!;
    if (_startAt == null) return 0;
    return math.max(0, DateTime.now().difference(_startAt!).inSeconds);
  }

  /// 运动时长（秒，不含暂停）
  int get activeDurationSecs {
    if (_activeSecsOverrideForTest != null) return _activeSecsOverrideForTest!;
    if (_startAt == null) return 0;
    final now = DateTime.now();
    var pausedMs = _accumulatedPausedMs;
    if (_paused && _pauseStartedAt != null) {
      pausedMs += now.difference(_pauseStartedAt!).inMilliseconds;
    }
    final activeMs = now.difference(_startAt!).inMilliseconds - pausedMs;
    return math.max(0, activeMs ~/ 1000);
  }

  /// 平均配速（秒/公里），距离 >= 20m 后开始计算
  int? get avgPaceSecsPerKm {
    final dist = _processor.distanceMeters;
    final active = activeDurationSecs;
    if (dist < 20 || active <= 0) return null;
    final pace = (active / (dist / 1000.0)).round();
    return pace.clamp(120, 2400);
  }

  int get caloriesKcal => estimateRunCalories(
        distanceMeters: _processor.distanceMeters,
        weightKg: weightKg,
        activeDurationSecs: activeDurationSecs,
      );

  Future<void> _speak(String text) async {
    final msg = text.trim();
    if (msg.isEmpty) return;
    if (onSpeakForTest != null) {
      if (!voiceCoach.isMuted) onSpeakForTest!(msg);
      return;
    }
    if (!_skipPlatformSideEffects) {
      try {
        await voiceCoach.speak(msg);
      } catch (e, st) {
        debugPrint('[VoiceCoach] _speak threw: $e\n$st');
      }
    }
  }

  Future<void> _speakSequence(
    List<String> lines, {
    Duration gap = const Duration(milliseconds: 800),
  }) async {
    final nonEmpty = [
      for (final s in lines)
        if (s.trim().isNotEmpty) s.trim(),
    ];
    if (nonEmpty.isEmpty) return;
    if (onSpeakForTest != null) {
      if (!voiceCoach.isMuted) {
        for (final line in nonEmpty) {
          onSpeakForTest!(line);
        }
      }
      return;
    }
    if (!_skipPlatformSideEffects) {
      try {
        await voiceCoach.speakSequence(nonEmpty, gap: gap);
      } catch (e, st) {
        debugPrint('[VoiceCoach] _speakSequence threw: $e\n$st');
      }
    }
  }

  String _buildCourseIntroLine(RunningCourse c, int totalSegments) {
    final mins = c.estimatedMinutes;
    if (isEnglish) {
      final minsPart = mins != null ? ', about $mins minutes' : '';
      return 'Starting ${c.localizedName(isEn: true)}, $totalSegments segments$minsPart.';
    }
    final minsPart = mins != null ? '，预计 $mins 分钟' : '';
    return '开始 ${c.name}，共 $totalSegments 段$minsPart';
  }

  Future<void> start({bool skipPlatformSideEffects = false}) async {
    if (_started) return;
    _skipPlatformSideEffects = skipPlatformSideEffects;
    _started = true;
    _paused = false;
    _finished = false;
    _startAt = DateTime.now();
    _accumulatedPausedMs = 0;
    _pauseStartedAt = null;
    _gpsError = null;
    _lastAnnouncedKm = 0;
    _voiceUnavailablePromptNeeded = false;

    if (!skipPlatformSideEffects) {
      final ttsOk = await voiceCoach.init(isEnglish: isEnglish);
      if (!ttsOk && courseEngine != null) {
        _voiceUnavailablePromptNeeded = true;
      }
      try {
        await WakelockPlus.enable();
      } catch (_) {}
      await RunningNativeService.startForegroundService(
        title: notificationTitle,
        body: _formatNotificationBody(),
      );
      _startLocationStream();
    } else if (simulateVoiceUnavailableForTest && courseEngine != null) {
      _voiceUnavailablePromptNeeded = true;
    }

    // 课程模式开跑即触发震动 + 第 1 段横幅 + 主动总述与第 1 段顺序语音播报（间隔 1.5s 防吞字）
    if (courseEngine != null && courseEngine!.current != null) {
      final firstSeg = courseEngine!.current!;
      if (!skipPlatformSideEffects) {
        HapticFeedback.mediumImpact();
      }
      _emitBanner(
        segment: firstSeg,
        segmentNumber: 1,
        totalSegments: courseEngine!.totalSegments,
      );
      final introLine = _buildCourseIntroLine(course!, courseEngine!.totalSegments);
      final firstCue = firstSeg.voice.trim().isNotEmpty
          ? firstSeg.voice.trim()
          : RunningCourseCatalog.segmentMeta(firstSeg.type)
              .localizedLabel(isEn: isEnglish);
      unawaited(
        _speakSequence(
          [introLine, firstCue],
          gap: const Duration(milliseconds: 1500),
        ),
      );
    }

    notifyListeners();

    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_finished) return;
      if (!_paused) {
        _tickCourseAndMilestones();
      }
      notifyListeners();
      if (!skipPlatformSideEffects) {
        final now = DateTime.now();
        if (_lastNotifSyncAt == null || now.difference(_lastNotifSyncAt!).inSeconds >= 3) {
          _lastNotifSyncAt = now;
          RunningNativeService.updateForegroundNotification(
            title: notificationTitle,
            body: _formatNotificationBody(),
          );
        }
      }
    });
  }

  void _emitBanner({
    required RunningCourseSegment? segment,
    required int segmentNumber,
    required int totalSegments,
    bool courseCompleted = false,
    bool forcedByTimeout = false,
  }) {
    _bannerSeq++;
    _latestBannerEvent = SegmentTransitionEvent(
      eventId: _bannerSeq,
      segment: segment,
      segmentNumber: segmentNumber,
      totalSegments: totalSegments,
      courseCompleted: courseCompleted,
      forcedByTimeout: forcedByTimeout,
    );
  }

  bool _tickCourseAndMilestones() {
    var segmentSwitched = false;
    if (courseEngine != null && !courseEngine!.isCompleted) {
      final res = courseEngine!.tick(
        totalDistance: _processor.distanceMeters,
        totalSeconds: activeDurationSecs,
      );
      if (res.advanced) {
        segmentSwitched = true;
        if (!_skipPlatformSideEffects) {
          HapticFeedback.mediumImpact();
        }
        if (res.courseCompleted) {
          if (!_skipPlatformSideEffects) {
            ReminderService.vibrateShort();
          }
          _emitBanner(
            segment: null,
            segmentNumber: courseEngine!.totalSegments,
            totalSegments: courseEngine!.totalSegments,
            courseCompleted: true,
            forcedByTimeout: res.forcedByTimeout,
          );
          unawaited(_speak(isEnglish ? 'Course completed! Great job.' : '课程已全部完成，太棒了！'));
        } else if (res.newSegment != null) {
          _emitBanner(
            segment: res.newSegment,
            segmentNumber: courseEngine!.currentIndex + 1,
            totalSegments: courseEngine!.totalSegments,
            forcedByTimeout: res.forcedByTimeout,
          );
          final cue = res.newSegment!.voice.trim().isNotEmpty
              ? res.newSegment!.voice
              : RunningCourseCatalog.segmentMeta(res.newSegment!.type)
                  .localizedLabel(isEn: isEnglish);
          unawaited(_speak(cue));
        }
      }
    }

    // 整公里震动 + 配速语音播报（即使 TTS 不可用也保留轻震动反馈；若本 tick 刚切段则语音让位给切段提醒）
    final completedKm = (_processor.distanceMeters / 1000.0).floor();
    if (completedKm > _lastAnnouncedKm) {
      _lastAnnouncedKm = completedKm;
      if (!_skipPlatformSideEffects) {
        HapticFeedback.lightImpact();
      }
      if (!segmentSwitched) {
        final pace = avgPaceSecsPerKm;
        if (pace != null) {
          final pm = pace ~/ 60;
          final ps = pace % 60;
          final msg = isEnglish
              ? '$completedKm kilometers completed. Average pace $pm minutes $ps seconds per kilometer.'
              : '已完成 $completedKm 公里，平均配速 $pm 分 $ps 秒';
          unawaited(_speak(msg));
        }
      }
    }
    return segmentSwitched;
  }

  /// 供测试同步推进时间并触发课程分段评估
  @visibleForTesting
  void advanceTestClock(int activeSecs) {
    _activeSecsOverrideForTest = activeSecs;
    if (!_paused && _started && !_finished) {
      _tickCourseAndMilestones();
    }
    notifyListeners();
  }

  /// 手动跳到课程下一段
  void skipCourseSegment() {
    if (courseEngine == null || courseEngine!.isCompleted || _finished) return;
    final res = courseEngine!.skipCurrentSegment();
    if (!res.advanced) return;
    if (!_skipPlatformSideEffects) {
      HapticFeedback.mediumImpact();
    }
    if (res.courseCompleted) {
      _emitBanner(
        segment: null,
        segmentNumber: courseEngine!.totalSegments,
        totalSegments: courseEngine!.totalSegments,
        courseCompleted: true,
      );
      unawaited(_speak(isEnglish ? 'Course completed! Great job.' : '课程已全部完成，太棒了！'));
    } else if (res.newSegment != null) {
      _emitBanner(
        segment: res.newSegment,
        segmentNumber: courseEngine!.currentIndex + 1,
        totalSegments: courseEngine!.totalSegments,
      );
      unawaited(_speak(res.newSegment!.voice));
    }
    notifyListeners();
  }

  void _startLocationStream() {
    _posSub?.cancel();
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 5,
            intervalDuration: const Duration(seconds: 2),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 5,
          );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _gpsError = null;
        _latestAccuracy = pos.accuracy;
        injectRawPoint(
          RoutePoint(
            lat: pos.latitude,
            lng: pos.longitude,
            t: pos.timestamp.millisecondsSinceEpoch,
            accuracy: pos.accuracy,
          ),
        );
      },
      onError: (Object err) {
        _gpsError = err.toString();
        notifyListeners();
      },
    );
  }

  /// 注入原始轨迹点（GPS 回调或测试模拟）
  bool injectRawPoint(RoutePoint point) {
    if (!_started || _finished) return false;
    _latestAccuracy = point.accuracy;
    final accepted = _processor.addRawPoint(point, isPaused: _paused);
    if (accepted) {
      _tickCourseAndMilestones();
      if (!_targetNotified &&
          courseEngine == null &&
          targetDistanceKm != null &&
          targetDistanceKm! > 0 &&
          distanceKm >= targetDistanceKm!) {
        _targetNotified = true;
        if (!_skipPlatformSideEffects) {
          ReminderService.vibrateShort();
        }
      }
      notifyListeners();
    }
    return accepted;
  }

  /// 暂停跑步：停止接收 GPS 点并切断分段，不累计运动时长
  void pause() {
    if (!_started || _paused || _finished) return;
    _paused = true;
    _pauseStartedAt = DateTime.now();
    _processor.markPauseBreak();
    _posSub?.pause();
    notifyListeners();
    if (!_skipPlatformSideEffects) {
      RunningNativeService.updateForegroundNotification(
        title: notificationTitle,
        body: _formatNotificationBody(),
      );
    }
  }

  /// 继续跑步：恢复 GPS 流并开启新轨迹段，不把暂停期间的距离算进去
  void resume() {
    if (!_started || !_paused || _finished) return;
    if (_pauseStartedAt != null) {
      _accumulatedPausedMs += DateTime.now().difference(_pauseStartedAt!).inMilliseconds;
    }
    _pauseStartedAt = null;
    _paused = false;
    _processor.markPauseBreak();
    if (_posSub != null && _posSub!.isPaused) {
      _posSub!.resume();
    }
    notifyListeners();
    if (!_skipPlatformSideEffects) {
      RunningNativeService.updateForegroundNotification(
        title: notificationTitle,
        body: _formatNotificationBody(),
      );
    }
  }

  /// 导出本次跑步的课程分段明细（自由跑返回空列表）
  List<RunSegmentRecord> buildFinalSegmentRecords() =>
      courseEngine?.buildSegmentRecords() ?? const [];

  /// 结束跑步并组装可入库的 RunRecord（课程模式自动标记 course_completed / course_incomplete）
  Future<RunRecord> finish({String? note}) async {
    final activeSecs = activeDurationSecs;
    final totalSecs = totalDurationSecs;
    final startMs = (_startAt ?? DateTime.now()).millisecondsSinceEpoch;
    final endMs = DateTime.now().millisecondsSinceEpoch;
    final effectiveNote = note ??
        (courseEngine != null
            ? (courseEngine!.isCompleted ? 'course_completed' : 'course_incomplete')
            : null);
    final record = RunRecord(
      date: fmtDate(_startAt ?? DateTime.now()),
      startTime: startMs,
      endTime: endMs,
      durationSecs: activeSecs,
      totalSecs: math.max(totalSecs, activeSecs),
      distanceM: _processor.distanceMeters,
      avgPaceSecsPerKm: avgPaceSecsPerKm,
      caloriesKcal: caloriesKcal,
      courseId: course?.id,
      routeJson: RoutePoint.encodeList(_processor.allPoints),
      note: effectiveNote,
    );
    await stopAndCleanup();
    return record;
  }

  Future<void> stopAndCleanup() async {
    _finished = true;
    _uiTicker?.cancel();
    _uiTicker = null;
    await _posSub?.cancel();
    _posSub = null;
    await voiceCoach.stop();
    if (!_skipPlatformSideEffects) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      await RunningNativeService.stopForegroundService();
    }
    notifyListeners();
  }

  String _formatNotificationBody() {
    final dist = distanceKm.toStringAsFixed(2);
    final dur = formatRunDuration(activeDurationSecs);
    final pace = formatRunPace(avgPaceSecsPerKm);
    final curSeg = courseEngine?.current;
    if (curSeg != null) {
      final segLabel = RunningCourseCatalog.segmentMeta(curSeg.type).localizedLabel(isEn: isEnglish);
      return '$segLabel · $dist km · $dur';
    }
    return '$dist km · $dur · $pace';
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _posSub?.cancel();
    _processor.reset();
    voiceCoach.dispose();
    if (!_finished && !_skipPlatformSideEffects) {
      WakelockPlus.disable().catchError((_) {});
      RunningNativeService.stopForegroundService();
    }
    super.dispose();
  }
}
