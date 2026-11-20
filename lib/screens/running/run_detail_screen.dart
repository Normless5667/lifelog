import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../db/repo.dart';
import '../../models/run_models.dart';
import '../../services/running_tracker.dart';
import '../../widgets/common.dart';

/// 跑步记录详情页：从数据库 route_json 还原并绘制完整地图轨迹 + 距离/时长/配速/热量 + 课程分段记录
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

class _RunDetailScreenState extends State<RunDetailScreen> {
  List<RunSegmentRecord> _segments = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialSegments != null) {
      _segments = widget.initialSegments!;
    } else if (widget.run.id != null) {
      _loadSegments();
    }
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
    final points = run.decodeRoute();
    final latLngs = points.map((p) => LatLng(p.lat, p.lng)).toList();
    final primary = AppColors.primary(context);
    final success = AppColors.success(context);
    final warning = AppColors.warning(context);
    final danger = AppColors.danger(context);
    final workoutColor = AppColors.moduleWorkout(context);

    final initialCenter =
        latLngs.isNotEmpty ? latLngs.first : const LatLng(20.9628, 105.9410);
    final hasBounds = latLngs.length >= 2 &&
        (latLngs.first.latitude != latLngs.last.latitude ||
            latLngs.first.longitude != latLngs.last.longitude);

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
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: 15.5,
                      initialCameraFit: hasBounds
                          ? CameraFit.bounds(
                              bounds: LatLngBounds.fromPoints(latLngs),
                              padding: const EdgeInsets.all(36),
                            )
                          : null,
                    ),
                    children: [
                      if (!widget.disableMapTilesForTest)
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.lifelog.lifelog',
                        ),
                      if (latLngs.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: latLngs,
                              strokeWidth: 5,
                              color: primary,
                            ),
                          ],
                        ),
                      if (latLngs.isNotEmpty)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: latLngs.first,
                              width: 18,
                              height: 18,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: success,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2.5),
                                ),
                              ),
                            ),
                            if (latLngs.length > 1)
                              Marker(
                                point: latLngs.last,
                                width: 18,
                                height: 18,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: danger,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  if (latLngs.isEmpty)
                    Positioned.fill(
                      child: Container(
                        color: AppColors.surfaceSubtle(context).withValues(alpha: 0.86),
                        alignment: Alignment.center,
                        padding: AppSpacing.cardPadding,
                        child: Text(
                          l.runDetailNoRoute,
                          style: AppTypography.bodySecondary(context),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                      l.runDetailRoutePoints(points.length),
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
            color: AppColors.softBg(context, segColor, lightAlpha: 0.16, darkAlpha: 0.26),
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
          style: AppTypography.metricMedium(context, color: color).copyWith(fontSize: 22),
        ),
      ],
    );
  }
}
