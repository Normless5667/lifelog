import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../db/repo.dart';
import '../../models/run_models.dart';
import '../../services/nutrition.dart';
import '../../services/running_tracker.dart';
import '../../widgets/common.dart';
import 'location_permission_guide.dart';
import 'run_detail_screen.dart';
import 'running_active_screen.dart';

/// 户外跑步首页（Keep 风格）：
/// - 顶部：当前位置 OpenStreetMap 实时预览 + © OpenStreetMap contributors
/// - 中部：三个开跑入口（自由跑 / 距离跑 / 跑步课程）
/// - 下部：推荐课程（加载 assets/running_courses.json）+ 最近跑步记录（点击可重绘轨迹）
class RunningHomeScreen extends StatefulWidget {
  const RunningHomeScreen({super.key});

  @override
  State<RunningHomeScreen> createState() => _RunningHomeScreenState();
}

class _RunningHomeScreenState extends State<RunningHomeScreen> {
  final MapController _mapCtrl = MapController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _coursesKey = GlobalKey();

  LatLng _previewCenter = const LatLng(20.9628, 105.9410);
  bool _hasCurrentFix = false;
  double _weightKg = 65;
  List<RunningCourse> _courses = [];
  List<RunRecord> _runs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Repo.dataVersion.addListener(_onRepoDataChanged);
    _load();
    _locatePreview();
  }

  @override
  void dispose() {
    Repo.dataVersion.removeListener(_onRepoDataChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onRepoDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final rec = await Repo.latestBodyRecordWithWeight();
    final weightKg = Nutrition.sanitizeWeightKg(rec?.weight) ?? 65;
    final courses = await RunningCourseCatalog.loadAll();
    final runs = await Repo.getRuns(limit: 30);
    if (!mounted) return;
    setState(() {
      _weightKg = weightKg;
      _courses = courses.where((c) => !c.isFree).toList();
      _runs = runs;
      _loading = false;
    });
  }

  Future<void> _locatePreview() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        return;
      }
      if (perm == LocationPermission.deniedForever) return;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        _movePreview(LatLng(last.latitude, last.longitude));
      }
      final cur = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      if (mounted) {
        _movePreview(LatLng(cur.latitude, cur.longitude));
      }
    } catch (_) {}
  }

  void _movePreview(LatLng pos) {
    setState(() {
      _previewCenter = pos;
      _hasCurrentFix = true;
    });
    try {
      _mapCtrl.move(pos, 15.5);
    } catch (_) {}
  }

  Future<void> _launchRun({double? targetDistanceKm, RunningCourse? course}) async {
    final ok = await ensureRunningPermissions(context);
    if (!ok || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunningActiveScreen(
          weightKg: _weightKg,
          targetDistanceKm: targetDistanceKm,
          course: course,
          initialCenter: _previewCenter,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openDistancePicker() async {
    final l = context.l10n;
    double selectedKm = 3.0;
    const presets = [1.0, 3.0, 5.0, 10.0];
    final chosen = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final primary = AppColors.primary(ctx);
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.runPickDistanceTitle, style: AppTypography.sectionTitle(ctx)),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final km in presets)
                      ChoiceChip(
                        label: Text('${km.toInt()} km'),
                        selected: selectedKm == km,
                        selectedColor: AppColors.softBg(ctx, primary, lightAlpha: 0.18, darkAlpha: 0.28),
                        onSelected: (_) => setS(() => selectedKm = km),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, selectedKm),
                  icon: const Icon(Icons.directions_run_rounded, size: 20),
                  label: Text(l.runPickDistanceBtn(selectedKm.toInt().toString())),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (chosen != null && mounted) {
      await _launchRun(targetDistanceKm: chosen);
    }
  }

  void _scrollToCourses() {
    final ctx = _coursesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: AppMotion.medium1,
        curve: AppMotion.standardCurve,
      );
    }
  }

  String _courseNameById(String? id) {
    if (id == null) return context.l10n.runModeFree;
    for (final c in _courses) {
      if (c.id == id) return c.localizedName(isEn: context.isEnLocale);
    }
    return context.l10n.runModeFree;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final teal = AppColors.teal(context);
    final workoutColor = AppColors.moduleWorkout(context);
    final isEn = context.isEnLocale;

    return Scaffold(
      appBar: AppBar(title: Text(l.runModuleTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                // 顶部地图预览卡片
                ClipRRect(
                  borderRadius: AppRadius.bXl,
                  child: SizedBox(
                    height: 200,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapCtrl,
                          options: MapOptions(
                            initialCenter: _previewCenter,
                            initialZoom: 15.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.lifelog.lifelog',
                            ),
                            if (_hasCurrentFix)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _previewCenter,
                                    width: 22,
                                    height: 22,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Material(
                            color: AppColors.surface(context).withValues(alpha: 0.92),
                            shape: const CircleBorder(),
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.my_location_rounded, size: 18, color: primary),
                              onPressed: () async {
                                final ok = await ensureRunningPermissions(context);
                                if (ok) _locatePreview();
                              },
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

                // 开始跑步三入口（自由跑 / 距离跑 / 跑步课程）
                SectionTitle(
                  l.runStartSection,
                  icon: Icons.directions_run_rounded,
                  iconColor: workoutColor,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _modeCard(
                        context,
                        icon: Icons.directions_run_rounded,
                        color: primary,
                        title: l.runModeFree,
                        subtitle: l.runModeFreeSub,
                        onTap: () => _launchRun(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _modeCard(
                        context,
                        icon: Icons.flag_rounded,
                        color: teal,
                        title: l.runModeDistance,
                        subtitle: l.runModeDistanceSub,
                        onTap: _openDistancePicker,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _modeCard(
                        context,
                        icon: Icons.menu_book_rounded,
                        color: workoutColor,
                        title: l.runModeCourse,
                        subtitle: l.runModeCourseSub,
                        onTap: _scrollToCourses,
                      ),
                    ),
                  ],
                ),

                // 推荐课程（assets/running_courses.json）
                SectionTitle(
                  key: _coursesKey,
                  l.runRecommendedCourses,
                  icon: Icons.local_fire_department_rounded,
                  iconColor: workoutColor,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    l.runCourseBatch2Hint,
                    style: AppTypography.caption(context),
                  ),
                ),
                for (final course in _courses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SurfaceCard(
                      padding: AppSpacing.cardCompactPadding,
                      onTap: () => _launchRun(
                        course: course,
                        targetDistanceKm: course.targetDistanceKm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.softBg(context, workoutColor),
                              borderRadius: AppRadius.bMd,
                            ),
                            child: Icon(
                              course.level >= 2 ? Icons.bolt_rounded : Icons.directions_run_rounded,
                              color: workoutColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  course.localizedName(isEn: isEn),
                                  style: AppTypography.cardTitle(context),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l.runCourseMeta(
                                    course.estimatedMinutes ?? 30,
                                    course.estimatedKcal ?? 200,
                                    course.levelLabel.isNotEmpty
                                        ? course.levelLabel
                                        : 'K${course.level}',
                                  ),
                                  style: AppTypography.caption(context, color: workoutColor),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  course.description,
                                  style: AppTypography.bodySecondary(context),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Icon(Icons.play_circle_filled_rounded, color: workoutColor, size: 28),
                        ],
                      ),
                    ),
                  ),

                // 最近跑步记录
                SectionTitle(
                  l.runRecentHistory,
                  icon: Icons.history_rounded,
                  iconColor: primary,
                ),
                if (_runs.isEmpty)
                  SurfaceCard(
                    padding: AppSpacing.cardPadding,
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.softBg(context, primary),
                            borderRadius: AppRadius.bMd,
                          ),
                          child: Icon(Icons.route_rounded, color: primary, size: 22),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            l.runEmptyHistory,
                            style: AppTypography.bodySecondary(context),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final r in _runs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: SurfaceCard(
                        padding: AppSpacing.cardCompactPadding,
                        onTap: () async {
                          final deleted = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RunDetailScreen(
                                run: r,
                                courseName: _courseNameById(r.courseId),
                              ),
                            ),
                          );
                          if (deleted == true && mounted) _load();
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.softBg(context, primary),
                                borderRadius: AppRadius.bMd,
                              ),
                              child: Icon(Icons.route_rounded, color: primary, size: 22),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '${r.distanceKm.toStringAsFixed(2)} km',
                                        style: AppTypography.cardTitle(context),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Text(
                                        _courseNameById(r.courseId),
                                        style: AppTypography.caption(context),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${r.date} · ${formatRunDuration(r.durationSecs)} · ${formatRunPace(r.avgPaceSecsPerKm)} · ${r.caloriesKcal} kcal',
                                    style: AppTypography.bodySecondary(context),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary(context)),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, color, lightAlpha: 0.14, darkAlpha: 0.24),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: AppTypography.cardTitle(context).copyWith(fontSize: 13.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.caption(context).copyWith(fontSize: 10.5),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
