import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../services/usage_telemetry_service.dart';
import '../../services/widget_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'exercise_library_screen.dart';
import 'workout_session_screen.dart';

/// 训练板块（v2.0）：
/// 1) 当前使用的 AI 训练计划卡片（支持选某一天直接一键开练）
/// 2) 力量训练会话历史 + 容量柱状图
/// 3) 独立有氧运动记录（按 MET 自动算消耗 kcal）
class WorkoutListScreen extends StatefulWidget {
  const WorkoutListScreen({super.key});

  @override
  State<WorkoutListScreen> createState() => _WorkoutListScreenState();
}

class _WorkoutSummary {
  final Workout workout;
  final List<String> exerciseNames;
  final String primaryCategory;
  final int workSets;
  final double volume;
  final double estCalories;

  _WorkoutSummary(
    this.workout,
    this.exerciseNames,
    this.primaryCategory,
    this.workSets,
    this.volume,
    this.estCalories,
  );
}

class _WorkoutListScreenState extends State<WorkoutListScreen> {
  List<_WorkoutSummary> _items = [];
  List<CardioRecord> _cardios = [];
  TrainingPlan? _plan;
  double _userWeightKg = 65;
  int _tab = 0; // 0=力量训练, 1=独立有氧
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rec = await Repo.latestBodyRecordWithWeight();
    final weightKg = rec?.weight ?? 65;
    final workouts = await Repo.getWorkouts(limit: 60);
    final cardios = await Repo.getCardioRecords(limit: 60);
    final plan = await Repo.getTrainingPlan();
    final exercises = await Repo.getExercises();
    final exMap = {for (final e in exercises) e.id: e};
    final out = <_WorkoutSummary>[];
    for (final w in workouts) {
      final sets = await Repo.getSets(w.id!);
      final names = <String>[];
      String? primaryCat;
      final strengthRows = <({double weight, int reps, bool isWarmup})>[];
      for (final s in sets) {
        final ex = exMap[s.exerciseId];
        final n = ex?.name ?? '';
        primaryCat ??= ex?.category;
        if (n.isNotEmpty && !names.contains(n)) names.add(n);
        if (ex != null && L10nHelper.isCardioCategory(ex.category)) continue;
        strengthRows.add((weight: s.weight, reps: s.reps, isWarmup: s.isWarmup));
      }
      final strengthStats = Nutrition.calcStrengthStats(strengthRows);
      final workSets = strengthStats.sets;
      final vol = strengthStats.volume;
      double mins = 0;
      if (w.endTime != null && w.endTime! > w.startTime) {
        mins = (w.endTime! - w.startTime) / 60000.0;
      }
      if (mins <= 1 && workSets > 0) mins = workSets * 2.5;
      final kcal = Nutrition.calcMetCalories(
        met: Nutrition.strengthMet,
        weightKg: weightKg,
        minutes: mins.clamp(0, 180),
      );
      out.add(_WorkoutSummary(
        w,
        names,
        primaryCat ?? L10nHelper.cardioOtherCategory,
        workSets,
        vol,
        kcal,
      ));
    }
    WidgetService.sync(force: true);
    if (!mounted) return;
    setState(() {
      _userWeightKg = weightKg;
      _items = out;
      _cardios = cardios;
      _plan = plan;
      _loading = false;
    });
  }

  Future<void> _startNew({List<TrainingPlanExercise>? planExercises, String? note}) async {
    UsageTelemetryService.instance.trackFeature('start_workout', 'tap');
    final now = DateTime.now();
    final id = await Repo.createWorkout(Workout(
      date: fmtDate(now),
      startTime: now.millisecondsSinceEpoch,
      note: note,
    ));
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutSessionScreen(
          workoutId: id,
          isNew: true,
          initialPlanExercises: planExercises,
        ),
      ),
    );
    _load();
  }

  Future<void> _openSession(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkoutSessionScreen(workoutId: id)),
    );
    _load();
  }

  Future<void> _addOrEditCardio([CardioRecord? existing]) async {
    final res = await showDialog<CardioRecord>(
      context: context,
      builder: (_) => _CardioEditDialog(existing: existing, weightKg: _userWeightKg),
    );
    if (res != null) {
      await Repo.saveCardioRecord(res);
      if (!mounted) return;
      toast(context, context.l10n.workoutCardioSavedToast(fmtNum(res.calories)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final workoutColor = AppColors.moduleWorkout(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, workoutColor, lightAlpha: 0.12, darkAlpha: 0.20),
                borderRadius: AppRadius.bSm,
                border: Border.all(color: AppColors.softBorder(context, workoutColor)),
              ),
              child: Icon(Icons.fitness_center_rounded, color: workoutColor, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                l.workoutTitle,
                style: AppTypography.pageTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.surfaceSubtle(context),
                foregroundColor: AppColors.textPrimary(context),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
                );
                _load();
              },
              icon: const Icon(Icons.grid_view_rounded, size: 17),
              label: Text(l.workoutExerciseLibBtn),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tab == 0 ? () => _startNew() : () => _addOrEditCardio(),
        elevation: 2,
        backgroundColor: workoutColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.bLg),
        icon: Icon(_tab == 0 ? Icons.play_arrow_rounded : Icons.directions_run_rounded),
        label: Text(
          _tab == 0 ? l.workoutStartStrengthBtn : l.workoutLogCardioBtn,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AppColors.surface(context),
                      selectedBackgroundColor: AppColors.softBg(
                        context,
                        workoutColor,
                        lightAlpha: 0.14,
                        darkAlpha: 0.22,
                      ),
                      selectedForegroundColor: workoutColor,
                      foregroundColor: AppColors.textSecondary(context),
                      side: BorderSide(color: AppColors.border(context)),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.bLg),
                    ),
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.fitness_center_rounded, size: 17),
                        label: Text(l.workoutTabStrength),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.directions_run_rounded, size: 17),
                        label: Text(l.workoutTabCardio),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                Expanded(
                  child: _tab == 0 ? _buildStrengthTab() : _buildCardioTab(),
                ),
              ],
            ),
    );
  }

  Widget _buildStrengthTab() {
    final l = context.l10n;
    final workoutColor = AppColors.moduleWorkout(context);
    final headerWidgets = <Widget>[
      if (_plan != null) ...[
        _activePlanCard(_plan!),
        const SizedBox(height: AppSpacing.md),
      ],
      if (_items.isNotEmpty) _volumeBarCard(),
      SectionTitle(
        l.workoutHistoryTitle,
        icon: Icons.history_rounded,
        iconColor: workoutColor,
      ),
    ];

    final bodyCount = _items.isEmpty ? 1 : _items.length;

    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: headerWidgets.length + bodyCount,
      itemBuilder: (_, idx) {
        if (idx < headerWidgets.length) {
          return headerWidgets[idx];
        }
        if (_items.isEmpty) {
          return EmptyHint(
            icon: Icons.fitness_center_rounded,
            text: l.workoutEmptyStrengthHint,
            actionLabel: l.workoutEmptyStrengthBtn,
            onAction: () => _startNew(),
          );
        }
        final it = _items[idx - headerWidgets.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _workoutItemCard(it),
        );
      },
    );
  }

  Widget _activePlanCard(TrainingPlan plan) {
    final l = context.l10n;
    final teal = AppColors.teal(context);
    return SurfaceCard(
      backgroundColor: AppColors.softBg(context, teal, lightAlpha: 0.06, darkAlpha: 0.12),
      borderColor: AppColors.softBorder(context, teal),
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, teal, lightAlpha: 0.14, darkAlpha: 0.22),
                  borderRadius: AppRadius.bSm,
                ),
                child: Icon(Icons.event_note_rounded, color: teal, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.workoutActivePlanTitle(plan.planName),
                      style: AppTypography.cardTitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      l.workoutTapSplitHint,
                      style: AppTypography.badge(context, color: teal),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: plan.days.map((d) {
              return ActionChip(
                avatar: Icon(Icons.play_circle_fill_rounded, size: 17, color: teal),
                label: Text(
                  l.workoutPlanSplitChip(d.day, d.focus, d.exercises.length),
                  style: AppTypography.badge(context, color: AppColors.textPrimary(context))
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                backgroundColor: AppColors.surface(context),
                side: BorderSide(color: AppColors.softBorder(context, teal)),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                onPressed: () => _startNew(
                  planExercises: d.exercises,
                  note: '${plan.planName} - ${d.day}(${d.focus})',
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCardioTab() {
    final l = context.l10n;
    final cardioColor = AppColors.moduleWorkout(context);
    if (_cardios.isEmpty) {
      return Center(
        child: EmptyHint(
          icon: Icons.directions_run_rounded,
          text: l.workoutEmptyCardioHint,
          actionLabel: l.workoutEmptyCardioBtn,
          onAction: () => _addOrEditCardio(),
        ),
      );
    }
    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: _cardios.length,
      itemBuilder: (_, i) {
        final c = _cardios[i];
        final typeLabel = L10nHelper.cardioTypeLabel(context, c.type);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SurfaceCard(
            onTap: () => _addOrEditCardio(c),
            padding: AppSpacing.cardCompactPadding,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, cardioColor),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(Icons.directions_run_rounded, color: cardioColor, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l.workoutCardioItemTitle(typeLabel, fmtNum(c.durationMinutes))}${c.distanceKm != null ? ' · ${fmtNum(c.distanceKm!, digits: 2)} km' : ''}',
                        style: AppTypography.cardTitle(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${L10nHelper.friendlyDateL10n(context, c.date)} · MET ${Nutrition.cardioMets[c.type] ?? 5.0}',
                        style: AppTypography.bodySecondary(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, cardioColor),
                    borderRadius: AppRadius.bSm,
                  ),
                  child: Text(
                    '-${fmtNum(c.calories)} kcal',
                    style: AppTypography.badge(context, color: cardioColor),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: AppColors.textTertiary(context),
                  ),
                  onPressed: () async {
                    if (await confirm(context, l.workoutDeleteCardioConfirm)) {
                      await Repo.deleteCardioRecord(c.id!);
                      _load();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 最近 7 次训练容量柱状可视化卡片（Strava/Keep 风格）
  Widget _volumeBarCard() {
    final l = context.l10n;
    final workoutColor = AppColors.moduleWorkout(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final recent = _items.take(7).toList().reversed.toList();
    final maxVol = recent.fold<double>(1, (m, e) => e.volume > m ? e.volume : m);

    return SurfaceCard(
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, workoutColor),
                  borderRadius: AppRadius.bSm,
                ),
                child: Icon(Icons.bar_chart_rounded, color: workoutColor, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l.workoutVolumeChartTitle,
                  style: AppTypography.cardTitle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 118,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: recent.map((it) {
                final ratio = (it.volume / maxVol).clamp(0.10, 1.0);
                final vis = categoryVisual(it.primaryCategory);
                final barColor = AppColors.adaptForDark(context, vis.color);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            fmtNum(it.volume),
                            style: AppTypography.badge(context).copyWith(fontSize: 10),
                          ),
                        ),
                        const SizedBox(height: 5),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 68 * ratio),
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          builder: (_, h, _) => Container(
                            height: h,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [barColor, barColor.withValues(alpha: 0.72)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                                bottom: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          it.workout.date.substring(5),
                          style: AppTypography.caption(context).copyWith(fontSize: 10),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workoutItemCard(_WorkoutSummary it) {
    final l = context.l10n;
    final w = it.workout;
    final durMin = w.endTime == null ? null : ((w.endTime! - w.startTime) ~/ 60000);
    final vis = categoryVisual(it.primaryCategory);
    final catColor = AppColors.adaptForDark(context, vis.color);
    final displayNames =
        it.exerciseNames.map((n) => L10nHelper.exerciseDisplayName(context, n)).toList();

    return SurfaceCard(
      onTap: () => _openSession(w.id!),
      padding: AppSpacing.cardCompactPadding,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, catColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(vis.icon, color: catColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayNames.isEmpty ? l.workoutEmptySessionTitle : displayNames.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle(context),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    L10nHelper.friendlyDateL10n(context, w.date),
                    if (durMin != null && durMin > 0) l.workoutSessionDuration(durMin),
                    l.workoutSessionSets(it.workSets),
                    if (it.volume > 0) l.workoutSessionVolume(fmtNum(it.volume)),
                    if (it.estCalories > 0) l.workoutSessionBurn(fmtNum(it.estCalories)),
                  ].join(' · '),
                  style: AppTypography.bodySecondary(context),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: AppColors.textTertiary(context),
            ),
            onPressed: () async {
              if (await confirm(context, l.workoutDeleteSessionConfirm)) {
                await Repo.deleteWorkout(w.id!);
                _load();
              }
            },
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary(context)),
        ],
      ),
    );
  }
}

class _CardioEditDialog extends StatefulWidget {
  final CardioRecord? existing;
  final double weightKg;

  const _CardioEditDialog({this.existing, required this.weightKg});

  @override
  State<_CardioEditDialog> createState() => _CardioEditDialogState();
}

class _CardioEditDialogState extends State<_CardioEditDialog> {
  late String _date;
  late String _type;
  late final TextEditingController _mins;
  late final TextEditingController _dist;
  late final TextEditingController _kcal;
  bool _manualKcal = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? today();
    _type = e?.type ?? L10nHelper.cardioDefaultType;
    if (!Nutrition.cardioMets.containsKey(_type)) _type = L10nHelper.cardioDefaultType;
    _mins = TextEditingController(text: e != null ? fmtNum(e.durationMinutes) : '30');
    _dist = TextEditingController(
      text: e?.distanceKm != null ? fmtNum(e!.distanceKm!, digits: 2) : '',
    );
    _kcal = TextEditingController(text: e != null ? fmtNum(e.calories) : '');
    if (e == null) _recalc();
  }

  @override
  void dispose() {
    _mins.dispose();
    _dist.dispose();
    _kcal.dispose();
    super.dispose();
  }

  void _recalc() {
    if (_manualKcal) return;
    final m = Nutrition.parsePlainDouble(_mins.text) ?? 0;
    final met = Nutrition.cardioMets[_type] ?? 5.0;
    final c = Nutrition.calcMetCalories(met: met, weightKg: widget.weightKg, minutes: m);
    _kcal.text = fmtNum(c);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const numKb = TextInputType.numberWithOptions(decimal: true);
    final met = Nutrition.cardioMets[_type] ?? 5.0;
    final cardioColor = AppColors.moduleWorkout(context);
    final teal = AppColors.teal(context);
    final warning = AppColors.warning(context);
    final info = AppColors.info(context);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, cardioColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.directions_run_rounded, color: cardioColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              widget.existing == null ? l.cardioDialogAddTitle : l.cardioDialogEditTitle,
              style: AppTypography.sectionTitle(context),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_rounded, color: teal),
              title: Text(
                L10nHelper.friendlyDateL10n(context, _date),
                style: AppTypography.subtitle(context),
              ),
              trailing: const Icon(Icons.edit_calendar_rounded, size: 18),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: parseDate(_date),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = fmtDate(d));
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.cardioTypeLabel,
                prefixIcon: Icon(Icons.directions_run_rounded, color: cardioColor),
              ),
              items: Nutrition.cardioMets.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text('${L10nHelper.cardioTypeLabel(context, e.key)} (MET ${e.value})'),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _type = v ?? _type;
                  _recalc();
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mins,
                    keyboardType: numKb,
                    onChanged: (_) => setState(_recalc),
                    decoration: InputDecoration(
                      labelText: l.cardioDurationLabel,
                      suffixText: l.cardioMinutesSuffix,
                      prefixIcon: Icon(Icons.timer_rounded, color: warning),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _dist,
                    keyboardType: numKb,
                    decoration: InputDecoration(
                      labelText: l.cardioDistanceLabel,
                      suffixText: 'km',
                      prefixIcon: Icon(Icons.place_rounded, color: info),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _kcal,
              keyboardType: numKb,
              onChanged: (_) => _manualKcal = true,
              decoration: InputDecoration(
                labelText: l.cardioEstBurnLabel(fmtNum(widget.weightKg, digits: 1), '$met'),
                suffixText: 'kcal',
                prefixIcon: Icon(Icons.local_fire_department_rounded, color: AppColors.danger(context)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton.icon(
          onPressed: () {
            final rawMins = Nutrition.parsePlainDouble(_mins.text) ?? 0;
            if (rawMins <= 0) {
              toast(context, l.cardioDurationRequired);
              return;
            }
            final mins = rawMins.clamp(0.5, 1440.0).toDouble();
            final rawDist = Nutrition.parsePlainDouble(_dist.text);
            final dist = rawDist == null ? null : rawDist.clamp(0.0, 500.0).toDouble();
            final rawKcal = Nutrition.parsePlainDouble(_kcal.text) ??
                Nutrition.calcMetCalories(
                  met: Nutrition.cardioMets[_type] ?? 5.0,
                  weightKg: widget.weightKg,
                  minutes: mins,
                );
            final kcal = rawKcal.clamp(0.0, Nutrition.maxSingleActivityBurnKcal).toDouble();
            Navigator.pop(
              context,
              CardioRecord(
                id: widget.existing?.id,
                date: _date,
                type: _type,
                durationMinutes: mins,
                distanceKm: dist,
                calories: kcal,
                createdAt: widget.existing?.createdAt,
              ),
            );
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(l.commonSave),
        ),
      ],
    );
  }
}
