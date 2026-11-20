import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../db/repo.dart';
import '../../models/run_models.dart';
import '../../services/running_tracker.dart';
import '../../widgets/common.dart';
import 'run_detail_screen.dart';

/// 跑步进行中全屏界面：
/// - 上半区：flutter_map + OpenStreetMap 实时轨迹绘制 + 当前位置蓝点 + 信号状态 + OSM 版权标注
/// - 下半区：超大字号 4 核心指标（距离 / 运动时长 / 配速 / 千卡）+ 目标进度条 + 暂停/结束双大按钮
/// - 屏幕常亮（wakelock_plus）+ Android 前台定位服务保活（锁屏/切后台不断轨）
class RunningActiveScreen extends StatefulWidget {
  final double weightKg;
  final double? targetDistanceKm;
  final RunningCourse? course;
  final LatLng? initialCenter;
  final RunningTrackerController? controllerForTest;
  final bool disableMapTilesForTest;
  final Future<int> Function(RunRecord run)? onSaveRunOverrideForTest;

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

  @override
  void initState() {
    super.initState();
    if (widget.controllerForTest != null) {
      _ctrl = widget.controllerForTest!;
      _ownsController = false;
    } else {
      _ctrl = RunningTrackerController(
        weightKg: widget.weightKg,
        targetDistanceKm: widget.targetDistanceKm ?? widget.course?.targetDistanceKm,
        course: widget.course,
      );
      _ownsController = true;
    }
    _ctrl.addListener(_onTrackerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_ctrl.isStarted) {
        _ctrl.start(skipPlatformSideEffects: widget.controllerForTest != null);
      }
    });
  }

  void _onTrackerUpdate() {
    if (!mounted) return;
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
    _ctrl.removeListener(_onTrackerUpdate);
    if (_ownsController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmFinish() async {
    if (_finishing) return;
    final l = context.l10n;
    final wasRunning = !_ctrl.isPaused;
    if (wasRunning) _ctrl.pause();

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.runFinishConfirmTitle, style: AppTypography.sectionTitle(ctx)),
        content: Text(
          l.runFinishConfirmDesc(
            _ctrl.distanceKm.toStringAsFixed(2),
            formatRunDuration(_ctrl.activeDurationSecs),
            _ctrl.caloriesKcal,
          ),
          style: AppTypography.body(ctx),
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

    final record = await _ctrl.finish();
    if (widget.onSaveRunOverrideForTest != null) {
      record.id = await widget.onSaveRunOverrideForTest!(record);
    } else {
      await Repo.saveRun(record);
    }
    if (!mounted) return;
    toast(context, l.runSavedToast(record.caloriesKcal));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(
          run: record,
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
            onPressed: () {
              Navigator.pop(ctx, true);
            },
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
        ),
        body: Column(
          children: [
            // 上半区：实时轨迹地图
            Expanded(
              flex: 5,
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

            // 下半区：超大 4 项实时数据 + 暂停/结束双按钮
            Expanded(
              flex: 6,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      if (_ctrl.isPaused)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs + 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.softBg(context, warning, lightAlpha: 0.16, darkAlpha: 0.24),
                            borderRadius: AppRadius.bMd,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.pause_circle_rounded, size: 16, color: warning),
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
                      if (targetKm != null && targetKm > 0) ...[
                        if (_ctrl.targetReached)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs + 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.softBg(context, success, lightAlpha: 0.16, darkAlpha: 0.26),
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
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                      // 超大 4 核心指标（2×2）
                      Expanded(
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
                                    fontSize: 42,
                                  ),
                                ),
                                Expanded(
                                  child: _bigMetric(
                                    context,
                                    key: const ValueKey('run_metric_duration_val'),
                                    value: formatRunDuration(_ctrl.activeDurationSecs),
                                    label: l.runMetricDuration,
                                    color: AppColors.textPrimary(context),
                                    fontSize: 38,
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
                                    fontSize: 34,
                                  ),
                                ),
                                Expanded(
                                  child: _bigMetric(
                                    context,
                                    key: const ValueKey('run_metric_kcal_val'),
                                    value: '${_ctrl.caloriesKcal}',
                                    label: l.runMetricCalories,
                                    color: workoutColor,
                                    fontSize: 34,
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
                      const SizedBox(height: AppSpacing.md),
                      // 暂停 / 继续 & 结束双大按钮
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 54,
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
                                  _ctrl.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                  size: 24,
                                ),
                                label: Text(
                                  _ctrl.isPaused ? l.runResumeBtn : l.runPauseBtn,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: FilledButton.icon(
                                key: const ValueKey('run_finish_btn'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: danger,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _confirmFinish,
                                icon: const Icon(Icons.stop_rounded, size: 24),
                                label: Text(
                                  l.runFinishBtn,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
