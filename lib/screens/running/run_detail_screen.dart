import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../db/repo.dart';
import '../../models/run_models.dart';
import '../../services/app_prefs.dart';
import '../../services/running_tracker.dart';
import '../../utils/route_speed_coloring.dart';
import '../../widgets/common.dart';
import '../../widgets/route_speed_overlay.dart';

/// 跑步记录详情页：
/// - 从数据库 route_json 还原地图轨迹，支持一笔画动态回放（尊重系统减弱动画设置）
/// - 距离 / 时长 / 平均配速 / 热量核心指标卡
/// - fl_chart 平滑配速曲线（纵轴越靠上配速越快）
/// - 课程分段实际完成明细
class RunDetailScreen extends StatefulWidget {
  final RunRecord run;
  final String? courseName;
  final List<RunSegmentRecord>? initialSegments;
  final bool disableMapTilesForTest;

  const RunDetailScreen({
    super.key,
    required this.run,
    this.courseName,
    this.initialSegments,
    this.disableMapTilesForTest = false,
  });

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen>
    with SingleTickerProviderStateMixin {
  List<RunSegmentRecord> _segments = const [];
  late final List<RoutePoint> _points;
  late final List<LatLng> _latLngs;
  late final List<ColoredRouteSegment> _coloredSegments;
  late final List<PaceCurveSample> _paceSamples;
  late final AnimationController _replayCtrl;
  late final Animation<double> _replayCurve;
  bool _replayStarted = false;
  late bool _colorBySpeed;

  @override
  void initState() {
    super.initState();
    _points = widget.run.decodeRoute();
    _latLngs = _points.map((p) => LatLng(p.lat, p.lng)).toList();
    _coloredSegments = RouteSpeedColoring.buildSegments(_points);
    _paceSamples = computePaceCurveSamples(_points);
    _colorBySpeed = AppPrefsController.instance.routeColorBySpeed;

    _replayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _replayCurve = CurvedAnimation(
      parent: _replayCtrl,
      curve: Curves.easeInOutCubic,
    );

    if (widget.initialSegments != null) {
      _segments = widget.initialSegments!;
    } else if (widget.run.id != null) {
      _loadSegments();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_replayStarted) return;
    _replayStarted = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || _latLngs.length < 2) {
      _replayCtrl.value = 1.0;
    } else {
      _replayCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _replayCtrl.dispose();
    super.dispose();
  }

  void _triggerReplay() {
    if (_latLngs.length < 2) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _replayCtrl.value = 1.0;
      return;
    }
    _replayCtrl.forward(from: 0.0);
  }

  List<LatLng> _interpolatedRoute(double progress) {
    if (_latLngs.length < 2 || progress >= 0.999) return _latLngs;
    final clamped = progress.clamp(0.0, 1.0);
    final scaled = clamped * (_latLngs.length - 1);
    final idx = scaled.floor().clamp(0, _latLngs.length - 2);
    final frac = scaled - idx;
    final a = _latLngs[idx];
    final b = _latLngs[idx + 1];
    final head = LatLng(
      a.latitude + (b.latitude - a.latitude) * frac,
      a.longitude + (b.longitude - a.longitude) * frac,
    );
    return [..._latLngs.sublist(0, idx + 1), head];
  }

  Future<void> _loadSegments() async {
    try {
      final list = await Repo.getRunSegments(widget.run.id!);
      if (!mounted) return;
      setState(() => _segments = list);
    } catch (_) {}
  }

  Future<void> _delete(BuildContext context) async {
    final l = context.l10n;
    if (widget.run.id == null) return;
    final ok = await confirm(context, l.runDetailDeleteConfirm);
    if (!ok || !context.mounted) return;
    await Repo.deleteRun(widget.run.id!);
    if (!context.mounted) return;
    toast(context, l.runDetailDeletedToast);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final run = widget.run;
    final primary = AppColors.primary(context);
    final success = AppColors.success(context);
    final warning = AppColors.warning(context);
    final danger = AppColors.danger(context);
    final workoutColor = AppColors.moduleWorkout(context);

    final initialCenter =
        _latLngs.isNotEmpty ? _latLngs.first : const LatLng(20.9628, 105.9410);
    final hasBounds = _latLngs.length >= 2 &&
        (_latLngs.first.latitude != _latLngs.last.latitude ||
            _latLngs.first.longitude != _latLngs.last.longitude);

    final isCourseCompleted = run.note == 'course_completed';
    final isCourseIncomplete = run.note == 'course_incomplete';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseName ?? l.runDetailTitle),
        actions: [
          if (run.id != null)
            IconButton(
              tooltip: l.commonDelete,
              icon: Icon(Icons.delete_outline_rounded, color: danger),
              onPressed: () => _delete(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          ClipRRect(
            borderRadius: AppRadius.bXl,
            child: SizedBox(
              height: 260,
              child: AnimatedBuilder(
                animation: _replayCtrl,
                builder: (context, _) {
                  final progress = _replayCurve.value;
                  final drawn = _interpolatedRoute(progress);
                  final isReplaying = _replayCtrl.isAnimating;
                  final activePolylines = _colorBySpeed && _coloredSegments.isNotEmpty
                      ? [
                          for (final seg in RouteSpeedColoring.sliceByProgress(
                            _coloredSegments,
                            progress,
                          ))
                            Polyline(
                              points: seg.points,
                              strokeWidth: 5,
                              color: seg.color,
                            ),
                        ]
                      : [
                          if (drawn.length >= 2)
                            Polyline(
                              points: drawn,
                              strokeWidth: 5,
                              color: primary,
                            ),
                        ];

                  return Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: 15.5,
                          initialCameraFit: hasBounds
                              ? CameraFit.bounds(
                                  bounds: LatLngBounds.fromPoints(_latLngs),
                                  padding: const EdgeInsets.all(36),
                                )
                              : null,
                        ),
                        children: [
                          if (!widget.disableMapTilesForTest)
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.lifelog.lifelog',
                            ),
                          if (activePolylines.isNotEmpty)
                            PolylineLayer(polylines: activePolylines),
                          if (drawn.isNotEmpty)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _latLngs.first,
                                  width: 18,
                                  height: 18,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: success,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                ),
                                if (drawn.length > 1)
                                  Marker(
                                    point: drawn.last,
                                    width: isReplaying ? 20 : 18,
                                    height: isReplaying ? 20 : 18,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isReplaying ? primary : danger,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2.5,
                                        ),
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
                              color: GeminiDarkColors.bgBottom
                                  .withValues(alpha: 0.24),
                            ),
                          ),
                        ),
                      if (_latLngs.isEmpty)
                        Positioned.fill(
                          child: Container(
                            color: AppColors.surfaceSubtle(context)
                                .withValues(alpha: 0.86),
                            alignment: Alignment.center,
                            padding: AppSpacing.cardPadding,
                            child: Text(
                              l.runDetailNoRoute,
                              style: AppTypography.bodySecondary(context),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      if (_latLngs.length >= 2)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: RouteColorModeToggle(
                            colorBySpeed: _colorBySpeed,
                            onChanged: (next) {
                              setState(() => _colorBySpeed = next);
                              AppPrefsController.instance.setRouteColorBySpeed(next);
                            },
                          ),
                        ),
                      if (_latLngs.length >= 2)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Material(
                            color: AppColors.surface(context)
                                .withValues(alpha: 0.90),
                            borderRadius: AppRadius.bPill,
                            child: InkWell(
                              key: const ValueKey('run_detail_replay_btn'),
                              onTap: _triggerReplay,
                              borderRadius: AppRadius.bPill,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.replay_rounded,
                                      size: 15,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isReplaying
                                          ? l.runDetailReplayingLabel
                                          : l.runDetailReplayBtn,
                                      style: AppTypography.badge(
                                        context,
                                        color: primary,
                                      ).copyWith(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_colorBySpeed && _latLngs.length >= 2) ...[
                              const RouteSpeedLegend(),
                              const SizedBox(height: 4),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface(context)
                                    .withValues(alpha: 0.85),
                                borderRadius: AppRadius.bSm,
                              ),
                              child: Text(
                                l.runOsmAttribution,
                                style: AppTypography.caption(context)
                                    .copyWith(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SurfaceCard(
            isHero: true,
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      run.date,
                      style: AppTypography.badge(context, color: primary),
                    ),
                    if (isCourseCompleted || isCourseIncomplete) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softBg(
                            context,
                            isCourseCompleted ? success : warning,
                          ),
                          borderRadius: AppRadius.bPill,
                        ),
                        child: Text(
                          isCourseCompleted
                              ? l.runCourseCompletedTag
                              : l.runCourseIncompleteTag,
                          style: AppTypography.badge(
                            context,
                            color: isCourseCompleted ? success : warning,
                          ).copyWith(fontSize: 10.5),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      l.runDetailRoutePoints(_points.length),
                      style: AppTypography.caption(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      run.distanceKm.toStringAsFixed(2),
                      style: AppTypography.displayMetric(context, color: primary)
                          .copyWith(fontSize: 44),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text('km', style: AppTypography.subtitle(context)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _statTile(
                        context,
                        label: l.runMetricDuration,
                        value: formatRunDuration(run.durationSecs),
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    Expanded(
                      child: _statTile(
                        context,
                        label: l.runMetricPace,
                        value: formatRunPace(run.avgPaceSecsPerKm),
                        color: primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _statTile(
                        context,
                        label: l.runMetricCalories,
                        value: '${run.caloriesKcal}',
                        color: workoutColor,
                      ),
                    ),
                    Expanded(
                      child: _statTile(
                        context,
                        label: l.runMetricTotalTime,
                        value: formatRunDuration(run.totalSecs),
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_paceSamples.length >= 2) ...[
            SectionTitle(
              l.runDetailPaceChartTitle,
              icon: Icons.show_chart_rounded,
              iconColor: primary,
            ),
            _buildPaceChartCard(context, primary),
          ],
          if (_segments.isNotEmpty) ...[
            SectionTitle(
              l.runDetailSegmentsTitle,
              icon: Icons.format_list_numbered_rounded,
              iconColor: primary,
            ),
            SurfaceCard(
              padding: AppSpacing.cardCompactPadding,
              child: Column(
                children: [
                  for (var i = 0; i < _segments.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    _segmentRow(context, _segments[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaceChartCard(BuildContext context, Color primary) {
    final l = context.l10n;
    final minPace = _paceSamples.map((e) => e.paceMinPerKm).reduce(math.min);
    final maxPace = _paceSamples.map((e) => e.paceMinPerKm).reduce(math.max);
    final pad = math.max(0.5, (maxPace - minPace) * 0.2);
    // 纵轴取反：配速数值越小（越快）显示在越上方
    final minY = -(maxPace + pad);
    final maxY = -math.max(1.5, minPace - pad);
    final maxX = _paceSamples.last.km;
    final minX = _paceSamples.first.km;
    final xSpan = math.max(0.1, maxX - minX);
    final spots = [
      for (final s in _paceSamples) FlSpot(s.km, -s.paceMinPerKm),
    ];

    return SurfaceCard(
      key: const ValueKey('run_detail_pace_chart_card'),
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.runDetailPaceChartSub,
            style: AppTypography.caption(context),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 185,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: math.max(0.5, (maxY - minY) / 3),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border(context).withValues(alpha: 0.45),
                    strokeWidth: 0.8,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: math.max(0.5, (maxY - minY) / 3),
                      getTitlesWidget: (v, _) => Text(
                        formatRunPace((-v * 60).round()),
                        style: AppTypography.caption(context)
                            .copyWith(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: math.max(0.1, xSpan / 3),
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${v.toStringAsFixed(1)}k',
                          style: AppTypography.caption(context)
                              .copyWith(fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surfaceSubtle(context),
                    getTooltipItems: (items) => items
                        .map(
                          (it) => LineTooltipItem(
                            '${it.x.toStringAsFixed(2)} km\n${formatRunPace((-it.y * 60).round())}',
                            AppTypography.badge(context, color: primary),
                          ),
                        )
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          primary.withValues(alpha: 0.28),
                          primary.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentRow(BuildContext context, RunSegmentRecord seg) {
    final meta = RunningCourseCatalog.segmentMeta(seg.type);
    final segColor = AppColors.adaptForDark(context, Color(meta.colorValue));
    final label = meta.localizedLabel(isEn: context.isEnLocale);
    final distKm = ((seg.distanceM ?? 0) / 1000.0).toStringAsFixed(2);
    final durStr = formatRunDuration(seg.durationSecs ?? 0);
    final paceStr = formatRunPace(seg.avgPaceSecsPerKm);

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.softBg(
              context,
              segColor,
              lightAlpha: 0.16,
              darkAlpha: 0.26,
            ),
            borderRadius: AppRadius.bSm,
          ),
          child: Text(
            '${seg.seq}',
            style: AppTypography.badge(context, color: segColor),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTypography.subtitle(context, color: segColor),
          ),
        ),
        Text(
          '$durStr · $distKm km · $paceStr',
          style: AppTypography.bodySecondary(context),
        ),
      ],
    );
  }

  Widget _statTile(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(context)),
        const SizedBox(height: 2),
        Text(
          value,
          style:
              AppTypography.metricMedium(context, color: color).copyWith(fontSize: 22),
        ),
      ],
    );
  }
}
