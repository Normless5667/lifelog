import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../db/repo.dart';
import '../../models/run_models.dart';
import '../../services/running_tracker.dart';
import '../../widgets/common.dart';

/// 跑步记录详情页：从数据库 route_json 还原并绘制完整地图轨迹 + 距离/时长/配速/热量
class RunDetailScreen extends StatelessWidget {
  final RunRecord run;
  final String? courseName;
  final bool disableMapTilesForTest;

  const RunDetailScreen({
    super.key,
    required this.run,
    this.courseName,
    this.disableMapTilesForTest = false,
  });

  Future<void> _delete(BuildContext context) async {
    final l = context.l10n;
    if (run.id == null) return;
    final ok = await confirm(context, l.runDetailDeleteConfirm);
    if (!ok || !context.mounted) return;
    await Repo.deleteRun(run.id!);
    if (!context.mounted) return;
    toast(context, l.runDetailDeletedToast);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final points = run.decodeRoute();
    final latLngs = points.map((p) => LatLng(p.lat, p.lng)).toList();
    final primary = AppColors.primary(context);
    final success = AppColors.success(context);
    final danger = AppColors.danger(context);
    final workoutColor = AppColors.moduleWorkout(context);

    final initialCenter =
        latLngs.isNotEmpty ? latLngs.first : const LatLng(20.9628, 105.9410);
    final hasBounds = latLngs.length >= 2 &&
        (latLngs.first.latitude != latLngs.last.latitude ||
            latLngs.first.longitude != latLngs.last.longitude);

    return Scaffold(
      appBar: AppBar(
        title: Text(courseName ?? l.runDetailTitle),
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
              height: 280,
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
                      if (!disableMapTilesForTest)
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
        ],
      ),
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
