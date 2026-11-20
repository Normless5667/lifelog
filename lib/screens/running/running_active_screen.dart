import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../db/repo.dart';
import '../../models/run_models.dart';
import '../../services/run_course_engine.dart';
import '../../services/running_tracker.dart';
import '../../widgets/common.dart';
import 'run_detail_screen.dart';

/// 跑步进行中全屏界面：
/// - 上半区：flutter_map + OpenStreetMap 实时轨迹绘制 + 当前位置蓝点 + 信号状态 + OSM 版权标注
/// - 课程模式下：顶部滑入切段横幅 + 显眼「当前分段卡片」（类型中文名 / 进度条 / 剩余秒或米 / 第 X 段共 Y 段）+ 底部「下一段预告」
/// - 核心区：超大字号 4 核心指标（距离 / 运动时长 / 配速 / 千卡）+ 暂停/结束双大按钮
/// - 屏幕常亮（wakelock_plus）+ Android 前台定位服务保活 + TTS 语音教练（压低音乐焦点，不可用自动降级）
class RunningActiveScreen extends StatefulWidget {
  final double weightKg;
  final double? targetDistanceKm;
  final RunningCourse? course;
  final LatLng? initialCenter;
  final RunningTrackerController? controllerForTest;
  final bool disableMapTilesForTest;
  final Future<int> Function(RunRecord run, List<RunSegmentRecord> segments)?
      onSaveRunOverrideForTest;

  const RunningActiveScreen({
    super.key,
    required this.weightKg,
    this.targetDistanceKm,
    this.course,
    this.initialCenter,
    this.controllerForTest,
    this.disableMapTilesForTest = false,
    this.onSaveRunOverrideForTest,
  });

  @override
  State<RunningActiveScreen> createState() => _RunningActiveScreenState();
}

class _RunningActiveScreenState extends State<RunningActiveScreen> {
  late final RunningTrackerController _ctrl;
  late final bool _ownsController;
  final MapController _mapCtrl = MapController();
  bool _followUser = true;
  bool _finishing = false;
  int _lastMovedPointCount = 0;

  int _lastBannerId = 0;
  SegmentTransitionEvent? _visibleBanner;
  Timer? _bannerHideTimer;

  @override
  void initState() {
    super.initState();
    final isEn = WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en';
    if (widget.controllerForTest != null) {
      _ctrl = widget.controllerForTest!;
      _ownsController = false;
    } else {
      _ctrl = RunningTrackerController(
        weightKg: widget.weightKg,
        targetDistanceKm: widget.targetDistanceKm ?? widget.course?.targetDistanceKm,
        course: widget.course,
        isEnglish: isEn,
      );
      _ownsController = true;
    }
    _ctrl.addListener(_onTrackerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_ctrl.isStarted) {
        _ctrl.start(skipPlatformSideEffects: widget.controllerForTest != null);
      } else {
        _syncBannerEvent();
      }
    });
  }

  void _syncBannerEvent() {
    final ev = _ctrl.latestBannerEvent;
    if (ev != null && ev.eventId != _lastBannerId) {
      _lastBannerId = ev.eventId;
      _bannerHideTimer?.cancel();
      _visibleBanner = ev;
      _bannerHideTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) {
          setState(() => _visibleBanner = null);
        }
      });
    }
  }

  void _onTrackerUpdate() {
    if (!mounted) return;
    _syncBannerEvent();
    final pts = _ctrl.allPoints;
    if (_followUser && pts.isNotEmpty && pts.length != _lastMovedPointCount) {
      _lastMovedPointCount = pts.length;
      final latest = pts.last;
      try {
        _mapCtrl.move(LatLng(latest.lat, latest.lng), _mapCtrl.camera.zoom);
      } catch (_) {}
    }
    setState(() {});
  }

  @override
  void dispose() {
    _bannerHideTimer?.cancel();
    _ctrl.removeListener(_onTrackerUpdate);
    if (_ownsController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  IconData _segmentIcon(String type) {
    switch (type) {
      case 'warmup':
        return Icons.whatshot_rounded;
      case 'fast':
        return Icons.bolt_rounded;
      case 'slow':
        return Icons.self_improvement_rounded;
      case 'walk':
        return Icons.directions_walk_rounded;
      case 'cooldown':
        return Icons.spa_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  String _formatRemainingForSegment(BuildContext context, RunCourseEngine engine) {
    final l = context.l10n;
    final remMeters = engine.remainingMeters;
    if (remMeters != null) {
      return l.runCourseRemainingMeters(remMeters.ceil());
    }
    final remSecs = engine.remainingSecs ?? 0;
    return l.runCourseRemainingTime(formatRunDuration(remSecs));
  }

  String _formatNextSegmentLine(BuildContext context, RunningCourseSegment? nextSeg) {
    final l = context.l10n;
    if (nextSeg == null) return l.runCourseNextFinal;
    final label = RunningCourseCatalog.segmentMeta(nextSeg.type)
        .localizedLabel(isEn: context.isEnLocale);
    if (nextSeg.isDistanceBased) {
      return l.runCourseNextSegmentMeters(label, nextSeg.durationMeters!.round());
    }
    return l.runCourseNextSegmentTime(label, nextSeg.durationSeconds ?? 0);
  }

  Future<void> _confirmFinish() async {
    if (_finishing) return;
    final l = context.l10n;
    final wasRunning = !_ctrl.isPaused;
    if (wasRunning) _ctrl.pause();

    final isEarlyIncomplete = _ctrl.hasCourseSegments && !_ctrl.isCourseCompleted;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.runFinishConfirmTitle, style: AppTypography.sectionTitle(ctx)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.runFinishConfirmDesc(
                _ctrl.distanceKm.toStringAsFixed(2),
                formatRunDuration(_ctrl.activeDurationSecs),
                _ctrl.caloriesKcal,
              ),
              style: AppTypography.body(ctx),
            ),
            if (isEarlyIncomplete) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: AppSpacing.cardCompactPadding,
                decoration: BoxDecoration(
                  color: AppColors.softBg(ctx, AppColors.warning(ctx)),
                  borderRadius: AppRadius.bMd,
                ),
                child: Text(
                  l.runCourseEarlyFinishHint,
                  style: AppTypography.caption(ctx, color: AppColors.warning(ctx)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger(ctx)),
            child: Text(l.runFinishDiscardBtn),
          ),
          FilledButton(
            key: const ValueKey('run_confirm_save_btn'),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(l.runFinishSaveBtn),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == null || action == 'cancel') {
      if (wasRunning) _ctrl.resume();
      return;
    }

    _finishing = true;
    if (action == 'discard') {
      await _ctrl.stopAndCleanup();
      if (mounted) Navigator.pop(context, false);
      return;
    }

    final segments = _ctrl.buildFinalSegmentRecords();
    final record = await _ctrl.finish();
    if (widget.onSaveRunOverrideForTest != null) {
      record.id = await widget.onSaveRunOverrideForTest!(record, segments);
    } else {
      await Repo.saveRun(record, segments: segments);
    }
    if (!mounted) return;
    toast(context, l.runSavedToast(record.caloriesKcal));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(
          run: record,
          initialSegments: segments,
          courseName: widget.course?.localizedName(isEn: context.isEnLocale),
          disableMapTilesForTest: widget.disableMapTilesForTest,
        ),
      ),
    );
  }

  Future<void> _onBackPressed() async {
    final l = context.l10n;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.runLeaveGuardTitle, style: AppTypography.sectionTitle(ctx)),
        content: Text(l.runLeaveGuardDesc, style: AppTypography.body(ctx)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.runFinishBtn),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      await _confirmFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final success = AppColors.success(context);
    final warning = AppColors.warning(context);
    final danger = AppColors.danger(context);
    final workoutColor = AppColors.moduleWorkout(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final latest = _ctrl.latestPoint;
    final center = latest != null
        ? LatLng(latest.lat, latest.lng)
        : (widget.initialCenter ?? const LatLng(20.9628, 105.9410));

    final polylines = <Polyline>[
      for (final seg in _ctrl.trackSegments)
        if (seg.length >= 2)
          Polyline(
            points: seg.map((p) => LatLng(p.lat, p.lng)).toList(),
            strokeWidth: 5,
            color: primary,
          ),
    ];

    final engine = _ctrl.courseEngine;
    final hasCourse = engine != null;
    final targetKm = _ctrl.targetDistanceKm;
    final acc = _ctrl.latestAccuracy;
    final gpsText = acc == null
        ? l.runGpsSearching
        : (acc <= RunTrackProcessor.maxAccuracyMeters
            ? l.runGpsSignalGood(acc.round())
            : l.runGpsSignalWeak(acc.round()));
    final gpsColor = acc == null
        ? AppColors.textSecondary(context)
        : (acc <= RunTrackProcessor.maxAccuracyMeters ? success : warning);

    final title = widget.course != null
        ? widget.course!.localizedName(isEn: context.isEnLocale)
        : (targetKm != null
            ? '${l.runModeDistance} · ${targetKm.toStringAsFixed(targetKm == targetKm.roundToDouble() ? 0 : 1)} km'
            : l.runModeFree);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _onBackPressed,
          ),
          actions: [
            IconButton(
              tooltip: _ctrl.isVoiceMuted ? l.runCourseVoiceOffTooltip : l.runCourseVoiceOnTooltip,
              icon: Icon(
                _ctrl.isVoiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              ),
              onPressed: _ctrl.toggleVoiceMute,
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // 上半区：实时轨迹地图
                Expanded(
                  flex: hasCourse ? 4 : 5,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapCtrl,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: 16.5,
                          onPositionChanged: (_, hasGesture) {
                            if (hasGesture && _followUser) {
                              setState(() => _followUser = false);
                            }
                          },
                        ),
                        children: [
                          if (!widget.disableMapTilesForTest)
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.lifelog.lifelog',
                            ),
                          if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                          if (latest != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(latest.lat, latest.lng),
                                  width: 24,
                                  height: 24,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: primary.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (AppColors.isMidnight(context))
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: GeminiDarkColors.bgBottom.withValues(alpha: 0.26),
                            ),
                          ),
                        ),
                      // GPS 信号胶囊
                      Positioned(
                        left: 12,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surface(context).withValues(alpha: 0.92),
                            borderRadius: AppRadius.bPill,
                            border: Border.all(color: AppColors.softBorder(context, gpsColor)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BreathingDot(color: gpsColor, size: 7),
                              const SizedBox(width: 6),
                              Text(
                                gpsText,
                                style: AppTypography.badge(context, color: gpsColor)
                                    .copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 回到当前位置按钮
                      Positioned(
                        right: 12,
                        bottom: 34,
                        child: FloatingActionButton.small(
                          heroTag: 'run_recenter_fab',
                          onPressed: () {
                            setState(() => _followUser = true);
                            _mapCtrl.move(center, 16.5);
                          },
                          child: Icon(
                            _followUser ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                      // OSM 版权声明（强制）
                      Positioned(
                        right: 10,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surface(context).withValues(alpha: 0.85),
                            borderRadius: AppRadius.bSm,
                          ),
                          child: Text(
                            l.runOsmAttribution,
                            style: AppTypography.caption(context).copyWith(fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 下半区：课程当前段指导卡 + 超大 4 项实时数据 + 下一段预告 + 暂停/结束双按钮
                Expanded(
                  flex: hasCourse ? 7 : 6,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Column(
                        children: [
                          if (hasCourse) ...[
                            _courseSegmentCard(context, engine),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          if (_ctrl.isPaused)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.softBg(
                                  context,
                                  warning,
                                  lightAlpha: 0.16,
                                  darkAlpha: 0.24,
                                ),
                                borderRadius: AppRadius.bMd,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.pause_circle_rounded, size: 15, color: warning),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      l.runPausedBanner,
                                      style: AppTypography.badge(context, color: warning),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (!hasCourse && targetKm != null && targetKm > 0) ...[
                            if (_ctrl.targetReached)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.xs + 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.softBg(
                                    context,
                                    success,
                                    lightAlpha: 0.16,
                                    darkAlpha: 0.26,
                                  ),
                                  borderRadius: AppRadius.bMd,
                                ),
                                child: Text(
                                  l.runTargetReachedBanner(targetKm.toStringAsFixed(1)),
                                  style: AppTypography.badge(context, color: success),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          l.runTargetProgress(
                                            _ctrl.distanceKm.toStringAsFixed(2),
                                            targetKm.toStringAsFixed(1),
                                          ),
                                          style: AppTypography.caption(context),
                                        ),
                                        Text(
                                          '${((_ctrl.distanceKm / targetKm) * 100).clamp(0, 100).round()}%',
                                          style: AppTypography.badge(context, color: primary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: AppRadius.bPill,
                                      child: LinearProgressIndicator(
                                        minHeight: 6,
                                        value: (_ctrl.distanceKm / targetKm).clamp(0.0, 1.0),
                                        color: primary,
                                        backgroundColor: AppColors.surfaceSubtle(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          // 超大 4 核心指标（2×2，自适应高度防小屏/大字号溢出）
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) => SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _bigMetric(
                                              context,
                                              key: const ValueKey('run_metric_distance_val'),
                                              value: _ctrl.distanceKm.toStringAsFixed(2),
                                              label: l.runMetricDistance,
                                              color: primary,
                                              fontSize: hasCourse ? 34 : 42,
                                            ),
                                          ),
                                          Expanded(
                                            child: _bigMetric(
                                              context,
                                              key: const ValueKey('run_metric_duration_val'),
                                              value: formatRunDuration(_ctrl.activeDurationSecs),
                                              label: l.runMetricDuration,
                                              color: AppColors.textPrimary(context),
                                              fontSize: hasCourse ? 32 : 38,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _bigMetric(
                                              context,
                                              key: const ValueKey('run_metric_pace_val'),
                                              value: formatRunPace(_ctrl.avgPaceSecsPerKm),
                                              label: l.runMetricPace,
                                              color: AppColors.textPrimary(context),
                                              fontSize: hasCourse ? 26 : 34,
                                            ),
                                          ),
                                          Expanded(
                                            child: _bigMetric(
                                              context,
                                              key: const ValueKey('run_metric_kcal_val'),
                                              value: '${_ctrl.caloriesKcal}',
                                              label: l.runMetricCalories,
                                              color: workoutColor,
                                              fontSize: hasCourse ? 26 : 34,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_ctrl.totalDurationSecs > _ctrl.activeDurationSecs + 1)
                                        Text(
                                          '${l.runMetricTotalTime}: ${formatRunDuration(_ctrl.totalDurationSecs)}',
                                          style: AppTypography.caption(context),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 课程模式底部「下一段预告」
                          if (hasCourse && !engine.isCompleted)
                            Container(
                              key: const ValueKey('run_course_next_strip'),
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs + 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSubtle(context),
                                borderRadius: AppRadius.bMd,
                                border: Border.all(color: AppColors.border(context)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.upcoming_rounded,
                                    size: 16,
                                    color: AppColors.textSecondary(context),
                                  ),
                                  const SizedBox(width: AppSpacing.xs + 2),
                                  Expanded(
                                    child: Text(
                                      _formatNextSegmentLine(context, engine.next),
                                      style: AppTypography.body(context).copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // 暂停 / 继续 & 结束双大按钮
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: FilledButton.tonalIcon(
                                    key: const ValueKey('run_pause_resume_btn'),
                                    onPressed: () {
                                      if (_ctrl.isPaused) {
                                        _ctrl.resume();
                                      } else {
                                        _ctrl.pause();
                                      }
                                    },
                                    icon: Icon(
                                      _ctrl.isPaused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      size: 24,
                                    ),
                                    label: Text(
                                      _ctrl.isPaused ? l.runResumeBtn : l.runPauseBtn,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: FilledButton.icon(
                                    key: const ValueKey('run_finish_btn'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          (hasCourse && engine.isCompleted) ? success : danger,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _confirmFinish,
                                    icon: Icon(
                                      (hasCourse && engine.isCompleted)
                                          ? Icons.check_circle_rounded
                                          : Icons.stop_rounded,
                                      size: 24,
                                    ),
                                    label: Text(
                                      l.runFinishBtn,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // 切段滑入横幅（2.4 秒后自动收起，遵循减少动画）
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.sm,
              child: IgnorePointer(
                child: AnimatedSlide(
                  offset: _visibleBanner != null ? Offset.zero : const Offset(0, -1.6),
                  duration: reduceMotion ? Duration.zero : AppMotion.medium1,
                  curve: AppMotion.standardCurve,
                  child: AnimatedOpacity(
                    opacity: _visibleBanner != null ? 1.0 : 0.0,
                    duration: reduceMotion ? Duration.zero : AppMotion.short4,
                    child: _visibleBanner == null
                        ? const SizedBox.shrink()
                        : _buildTransitionBanner(context, _visibleBanner!),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 当前课程分段卡片（显示类型中文名 + 第 X/Y 段总进度 + 进度条 + 剩余秒/米 + 语音文案）
  Widget _courseSegmentCard(BuildContext context, RunCourseEngine engine) {
    final l = context.l10n;
    final success = AppColors.success(context);

    if (engine.isCompleted) {
      return Container(
        key: const ValueKey('run_course_completed_card'),
        width: double.infinity,
        padding: AppSpacing.cardCompactPadding,
        decoration: BoxDecoration(
          color: AppColors.softBg(context, success, lightAlpha: 0.16, darkAlpha: 0.26),
          borderRadius: AppRadius.bLg,
          border: Border.all(color: AppColors.softBorder(context, success)),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: success, size: 26),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.runCourseCompletedTag,
                    style: AppTypography.cardTitle(context, color: success),
                  ),
                  Text(
                    l.runCourseCompletedBanner,
                    style: AppTypography.caption(context, color: success),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final seg = engine.current!;
    final meta = RunningCourseCatalog.segmentMeta(seg.type);
    final segColor = AppColors.adaptForDark(context, Color(meta.colorValue));
    final segLabel = meta.localizedLabel(isEn: context.isEnLocale);
    final remainStr = _formatRemainingForSegment(context, engine);

    return Container(
      key: const ValueKey('run_course_current_card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + 2,
        AppSpacing.md,
        AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.softBg(context, segColor, lightAlpha: 0.12, darkAlpha: 0.20),
        borderRadius: AppRadius.bLg,
        border: Border.all(
          color: AppColors.softBorder(context, segColor, lightAlpha: 0.42, darkAlpha: 0.50),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶行：当前段类型+中文名 + 剩余时间/米数 + 跳过按钮
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, segColor, lightAlpha: 0.22, darkAlpha: 0.30),
                  borderRadius: AppRadius.bSm,
                ),
                child: Icon(_segmentIcon(seg.type), color: segColor, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segLabel,
                      key: const ValueKey('run_course_current_label'),
                      style: AppTypography.sectionTitle(context, color: segColor),
                    ),
                    Text(
                      l.runCourseSegmentProgress(engine.currentIndex + 1, engine.totalSegments),
                      key: const ValueKey('run_course_overall_step'),
                      style: AppTypography.caption(context),
                    ),
                  ],
                ),
              ),
              Text(
                remainStr,
                key: const ValueKey('run_course_remaining_text'),
                style: AppTypography.metricLarge(context, color: segColor).copyWith(fontSize: 18),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('run_course_skip_btn'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                tooltip: l.runCourseSkipSegmentTooltip,
                icon: Icon(Icons.skip_next_rounded, size: 20, color: segColor),
                onPressed: _ctrl.skipCourseSegment,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          // 当前段进度条
          ClipRRect(
            borderRadius: AppRadius.bPill,
            child: LinearProgressIndicator(
              key: const ValueKey('run_course_segment_progress_bar'),
              minHeight: 7,
              value: engine.segmentProgress,
              color: segColor,
              backgroundColor: AppColors.surface(context).withValues(alpha: 0.65),
            ),
          ),
          if (seg.voice.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              seg.voice,
              style: AppTypography.bodySecondary(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          // 整门课程总进度细条
          ClipRRect(
            borderRadius: AppRadius.bPill,
            child: LinearProgressIndicator(
              minHeight: 3,
              value: engine.overallProgress,
              color: AppColors.primary(context),
              backgroundColor: AppColors.border(context).withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionBanner(BuildContext context, SegmentTransitionEvent ev) {
    final l = context.l10n;
    final success = AppColors.success(context);

    if (ev.courseCompleted) {
      return Material(
        key: const ValueKey('run_course_transition_banner'),
        elevation: 4,
        borderRadius: AppRadius.bLg,
        color: success,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l.runCourseCompletedBanner,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final seg = ev.segment!;
    final meta = RunningCourseCatalog.segmentMeta(seg.type);
    final segColor = AppColors.adaptForDark(context, Color(meta.colorValue));
    final label = meta.localizedLabel(isEn: context.isEnLocale);
    final amount = seg.isDistanceBased
        ? l.runCourseSegmentStepMeters(seg.durationMeters!.round())
        : (seg.durationSeconds != null && seg.durationSeconds! >= 60 && seg.durationSeconds! % 60 == 0
            ? l.runCourseSegmentStepMins(seg.durationSeconds! ~/ 60)
            : l.runCourseSegmentStepSecs(seg.durationSeconds ?? 0));

    return Material(
      key: const ValueKey('run_course_transition_banner'),
      elevation: 4,
      borderRadius: AppRadius.bLg,
      color: AppColors.surface(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          borderRadius: AppRadius.bLg,
          border: Border.all(color: segColor, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, segColor, lightAlpha: 0.18, darkAlpha: 0.28),
                borderRadius: AppRadius.bSm,
              ),
              child: Icon(_segmentIcon(seg.type), color: segColor, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$label · $amount (${ev.segmentNumber}/${ev.totalSegments})',
                    style: AppTypography.cardTitle(context, color: segColor),
                  ),
                  if (ev.forcedByTimeout)
                    Text(
                      l.runCourseTimeoutSwitched,
                      style: AppTypography.caption(context),
                    )
                  else if (seg.voice.isNotEmpty)
                    Text(
                      seg.voice,
                      style: AppTypography.caption(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigMetric(
    BuildContext context, {
    Key? key,
    required String value,
    required String label,
    required Color color,
    required double fontSize,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            key: key,
            style: AppTypography.displayMetric(context, color: color).copyWith(fontSize: fontSize),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.caption(context)),
      ],
    );
  }
}
