import 'dart:math' as math;

import '../models/run_models.dart';

/// 单次 tick 的课程状态变更结果
class RunCourseTickResult {
  /// 本次 tick 是否触发了切段（或课程收尾完成）
  final bool advanced;

  /// 是否刚刚跑完最后一段（整门课程完成）
  final bool courseCompleted;

  /// 是否由「3 倍时长超时兜底」强制切段（防止 GPS 信号差时距离不动卡死）
  final bool forcedByTimeout;

  /// 切入的新分段（若课程已全部完成则为 null）
  final RunningCourseSegment? newSegment;

  const RunCourseTickResult({
    this.advanced = false,
    this.courseCompleted = false,
    this.forcedByTimeout = false,
    this.newSegment,
  });

  static const RunCourseTickResult none = RunCourseTickResult();
}

/// 跑步课程分段执行引擎（纯 Dart，零平台依赖）：
/// - 同时支持按时间（durationSeconds，如法特莱克）与按距离（durationMeters，如 3/5/10km 分段跑、5×400m 间歇）
/// - 支持暂停隔离（调用方传入不含暂停的 activeDurationSecs 与有效 distanceMeters）
/// - 支持三种结束/推进判定：正常达标切段 / 用户提前结束（记录未完成但保留分段数据）/ 3 倍时长超时强制切段防卡死
class RunCourseEngine {
  final RunningCourse course;

  int _currentIndex = 0;
  int _segmentStartSecs = 0;
  double _segmentStartDistanceM = 0;
  int _lastTotalSecs = 0;
  double _lastTotalDistanceM = 0;
  bool _completed = false;
  final List<RunSegmentRecord> _completedRecords = [];

  RunCourseEngine(this.course) {
    if (course.segments.isEmpty) {
      _completed = true;
    }
  }

  bool get hasSegments => course.segments.isNotEmpty;
  bool get isCompleted => _completed;
  int get currentIndex => _currentIndex;
  int get totalSegments => course.segments.length;

  /// 当前正在执行的分段（已全部完成或自由跑时返回 null）
  RunningCourseSegment? get current =>
      (!_completed && _currentIndex < course.segments.length)
          ? course.segments[_currentIndex]
          : null;

  /// 下一分段（用于底部提前预告，让用户有心理准备）
  RunningCourseSegment? get next =>
      (!_completed && _currentIndex + 1 < course.segments.length)
          ? course.segments[_currentIndex + 1]
          : null;

  /// 当前段已运动时长（秒，不含暂停）
  int get segmentElapsedSecs => math.max(0, _lastTotalSecs - _segmentStartSecs);

  /// 当前段已跑距离（米）
  double get segmentElapsedMeters =>
      math.max(0.0, _lastTotalDistanceM - _segmentStartDistanceM);

  /// 当前段已完成比例（0.0 ~ 1.0）
  double get segmentProgress {
    if (_completed) return 1.0;
    final cur = current;
    if (cur == null) return 0.0;
    if (cur.isDistanceBased) {
      return (segmentElapsedMeters / cur.durationMeters!).clamp(0.0, 1.0);
    }
    if (cur.durationSeconds != null && cur.durationSeconds! > 0) {
      return (segmentElapsedSecs / cur.durationSeconds!).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// 整门课程总进度（0.0 ~ 1.0）
  double get overallProgress {
    if (!hasSegments) return 0.0;
    if (_completed) return 1.0;
    return ((_currentIndex + segmentProgress) / totalSegments).clamp(0.0, 1.0);
  }

  /// 按时间分段时还剩多少秒（按距离分段时返回 null）
  int? get remainingSecs {
    final cur = current;
    if (cur == null || cur.isDistanceBased || cur.durationSeconds == null) {
      return null;
    }
    return math.max(0, cur.durationSeconds! - segmentElapsedSecs);
  }

  /// 按距离分段时还剩多少米（按时间分段时返回 null）
  double? get remainingMeters {
    final cur = current;
    if (cur == null || !cur.isDistanceBased) return null;
    return math.max(0.0, cur.durationMeters! - segmentElapsedMeters);
  }

  /// 计算该分段的预期基准用时（秒），用于「3 倍时长超时强制切段」防卡死
  static int expectedSegmentDurationSecs(RunningCourseSegment seg) {
    if (!seg.isDistanceBased && seg.durationSeconds != null && seg.durationSeconds! > 0) {
      return seg.durationSeconds!;
    }
    if (seg.isDistanceBased) {
      // 按保守慢跑/快走配速 7'30"/km（0.45 秒/米）估算基准时长，最低 60 秒
      return math.max(60, (seg.durationMeters! * 0.45).round());
    }
    return 180;
  }

  /// 当前段是否已达到 3 倍基准时长超时阈值
  bool get isCurrentSegmentTimedOut {
    final cur = current;
    if (cur == null) return false;
    return segmentElapsedSecs >= expectedSegmentDurationSecs(cur) * 3;
  }

  /// 每次 1 秒 tick 或新 GPS 点进来时调用（暂停时不应调用）
  RunCourseTickResult tick({
    required double totalDistance,
    required int totalSeconds,
  }) {
    _lastTotalDistanceM = math.max(_lastTotalDistanceM, totalDistance);
    _lastTotalSecs = math.max(_lastTotalSecs, totalSeconds);

    if (_completed || current == null) {
      return RunCourseTickResult.none;
    }

    final reachedTarget = segmentProgress >= 1.0;
    final timedOut = !reachedTarget && isCurrentSegmentTimedOut;

    if (!reachedTarget && !timedOut) {
      return RunCourseTickResult.none;
    }

    _recordSegment(
      seq: _currentIndex + 1,
      seg: current!,
      durationSecs: segmentElapsedSecs,
      distanceM: segmentElapsedMeters,
    );

    _currentIndex++;
    _segmentStartSecs = _lastTotalSecs;
    _segmentStartDistanceM = _lastTotalDistanceM;

    if (_currentIndex >= course.segments.length) {
      _completed = true;
      return RunCourseTickResult(
        advanced: true,
        courseCompleted: true,
        forcedByTimeout: timedOut,
        newSegment: null,
      );
    }

    return RunCourseTickResult(
      advanced: true,
      courseCompleted: false,
      forcedByTimeout: timedOut,
      newSegment: current,
    );
  }

  /// 手动跳到下一段（例如室内测试或用户跳过热身）
  RunCourseTickResult skipCurrentSegment() {
    if (_completed || current == null) return RunCourseTickResult.none;
    _recordSegment(
      seq: _currentIndex + 1,
      seg: current!,
      durationSecs: segmentElapsedSecs,
      distanceM: segmentElapsedMeters,
    );
    _currentIndex++;
    _segmentStartSecs = _lastTotalSecs;
    _segmentStartDistanceM = _lastTotalDistanceM;
    if (_currentIndex >= course.segments.length) {
      _completed = true;
      return const RunCourseTickResult(
        advanced: true,
        courseCompleted: true,
        newSegment: null,
      );
    }
    return RunCourseTickResult(
      advanced: true,
      courseCompleted: false,
      newSegment: current,
    );
  }

  void _recordSegment({
    required int seq,
    required RunningCourseSegment seg,
    required int durationSecs,
    required double distanceM,
  }) {
    int? pace;
    if (distanceM >= 20 && durationSecs > 0) {
      pace = (durationSecs / (distanceM / 1000.0)).round().clamp(120, 2400);
    }
    _completedRecords.add(
      RunSegmentRecord(
        runId: 0,
        seq: seq,
        type: seg.type,
        durationSecs: durationSecs,
        distanceM: distanceM,
        avgPaceSecsPerKm: pace,
      ),
    );
  }

  /// 导出全部已跑分段记录（含提前结束时正在进行的当前段），供写入 SQLite run_segments 表
  List<RunSegmentRecord> buildSegmentRecords() {
    final out = List<RunSegmentRecord>.from(_completedRecords);
    if (!_completed && current != null && (segmentElapsedSecs > 0 || segmentElapsedMeters > 0)) {
      int? pace;
      if (segmentElapsedMeters >= 20 && segmentElapsedSecs > 0) {
        pace = (segmentElapsedSecs / (segmentElapsedMeters / 1000.0))
            .round()
            .clamp(120, 2400);
      }
      out.add(
        RunSegmentRecord(
          runId: 0,
          seq: _currentIndex + 1,
          type: current!.type,
          durationSecs: segmentElapsedSecs,
          distanceM: segmentElapsedMeters,
          avgPaceSecsPerKm: pace,
        ),
      );
    }
    return out;
  }
}
