import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/run_models.dart';
import '../utils/date_utils.dart';
import 'reminder_service.dart';

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

/// 根据距离（米）与体重（kg）估算跑步热量消耗（kcal）
int estimateRunCalories({
  required double distanceMeters,
  required double weightKg,
  required int activeDurationSecs,
}) {
  final w = weightKg.clamp(30.0, 200.0);
  if (distanceMeters >= 50) {
    // 经典跑步能量公式：约 1.036 kcal / kg / km
    return (1.036 * w * (distanceMeters / 1000.0)).round().clamp(0, 5000);
  }
  if (activeDurationSecs >= 30) {
    // 距离极短时的低速兜底估算
    return (w * 6.0 * (activeDurationSecs / 3600.0)).round().clamp(0, 500);
  }
  return 0;
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
}

/// 跑步会话实时控制器：
/// - 使用 Geolocator.getPositionStream(distanceFilter: 5) 省电追踪，绝不定时轮询
/// - 启动 Android 前台定位服务（常驻通知「正在记录跑步」）防止切后台断轨
/// - 使用单调真实时钟区分「运动时长（不含暂停）」与「总时长（含暂停）」
/// - 屏幕常亮（wakelock_plus）
class RunningTrackerController extends ChangeNotifier {
  final double weightKg;
  final double? targetDistanceKm;
  final RunningCourse? course;
  final String notificationTitle;

  final RunTrackProcessor _processor = RunTrackProcessor();
  StreamSubscription<Position>? _posSub;
  Timer? _uiTicker;

  bool _started = false;
  bool _paused = false;
  bool _finished = false;
  bool _targetNotified = false;
  bool _skipPlatformSideEffects = false;

  DateTime? _startAt;
  DateTime? _pauseStartedAt;
  int _accumulatedPausedMs = 0;
  DateTime? _lastNotifSyncAt;
  double? _latestAccuracy;
  String? _gpsError;

  RunningTrackerController({
    required this.weightKg,
    this.targetDistanceKm,
    this.course,
    this.notificationTitle = '正在记录跑步',
  });

  bool get isStarted => _started;
  bool get isPaused => _paused;
  bool get isFinished => _finished;
  bool get targetReached => _targetNotified;
  double? get latestAccuracy => _latestAccuracy;
  String? get gpsError => _gpsError;
  DateTime? get startAt => _startAt;

  double get distanceMeters => _processor.distanceMeters;
  double get distanceKm => _processor.distanceMeters / 1000.0;
  List<List<RoutePoint>> get trackSegments => _processor.segments;
  List<RoutePoint> get allPoints => _processor.allPoints;
  RoutePoint? get latestPoint => _processor.latestPoint;

  /// 总时长（秒，含暂停）
  int get totalDurationSecs {
    if (_startAt == null) return 0;
    return math.max(0, DateTime.now().difference(_startAt!).inSeconds);
  }

  /// 运动时长（秒，不含暂停）
  int get activeDurationSecs {
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
    notifyListeners();

    if (!skipPlatformSideEffects) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
      await RunningNativeService.startForegroundService(
        title: notificationTitle,
        body: _formatNotificationBody(),
      );
      _startLocationStream();
    }

    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_finished) return;
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
      if (!_targetNotified &&
          targetDistanceKm != null &&
          targetDistanceKm! > 0 &&
          distanceKm >= targetDistanceKm!) {
        _targetNotified = true;
        ReminderService.vibrateShort();
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

  /// 结束跑步并组装可入库的 RunRecord
  Future<RunRecord> finish({String? note}) async {
    final activeSecs = activeDurationSecs;
    final totalSecs = totalDurationSecs;
    final startMs = (_startAt ?? DateTime.now()).millisecondsSinceEpoch;
    final endMs = DateTime.now().millisecondsSinceEpoch;
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
      note: note,
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
    return '$dist km · $dur · $pace';
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _posSub?.cancel();
    if (!_finished && !_skipPlatformSideEffects) {
      WakelockPlus.disable().catchError((_) {});
      RunningNativeService.stopForegroundService();
    }
    super.dispose();
  }
}
