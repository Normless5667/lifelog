import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../services/usage_telemetry_service.dart';
import '../../services/widget_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../../widgets/in_progress_workout_card.dart';
import '../ai/ai_chat_screen.dart';
import 'exercise_library_screen.dart';
import 'workout_session_screen.dart';

/// 训练板块（v2.0）：
/// 1) 当前使用的 AI 训练计划卡片（支持选某一天直接一键开练）
/// 2) 力量训练会话历史 + 容量柱状图 + 手动修正 + 快速补录
/// 3) 独立有氧运动记录（按 MET 自动算消耗 kcal，支持手动修正）
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
  final double autoCalories;

  _WorkoutSummary(
    this.workout,
    this.exerciseNames,
    this.primaryCategory,
    this.workSets,
    this.volume,
    this.estCalories,
    this.autoCalories,
  );
}

class _WorkoutListScreenState extends State<WorkoutListScreen> {
  List<_WorkoutSummary> _items = [];
  List<CardioRecord> _cardios = [];
  List<Exercise> _exercises = [];
  InProgressWorkoutSnapshot? _inProgress;
  TrainingPlan? _plan;
  double _userWeightKg = 65;
  int _tab = 0; // 0=力量训练, 1=独立有氧
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Repo.dataVersion.addListener(_onRepoDataChanged);
    _load();
  }

  @override
  void dispose() {
    Repo.dataVersion.removeListener(_onRepoDataChanged);
    super.dispose();
  }

  void _onRepoDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final rec = await Repo.latestBodyRecordWithWeight();
    final weightKg = Nutrition.sanitizeWeightKg(rec?.weight) ?? 65;
    final workouts = await Repo.getWorkouts(limit: 60);
    final cardios = await Repo.getCardioRecords(limit: 60);
    final plan = await Repo.getTrainingPlan();
    final exercises = await Repo.getExercises();
    final inProgress = await InProgressWorkoutHelper.loadSnapshot(weightKg: weightKg);
    final exMap = {for (final e in exercises) e.id: e};
    final out = <_WorkoutSummary>[];
    for (final w in workouts) {
      // 进行中的训练单独展示在顶部「🔴 训练进行中」恢复卡片，不混入已完成历史
      if (w.endTime == null) continue;
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
      double elapsedMins = 0;
      if (w.endTime != null && w.endTime! > w.startTime) {
        elapsedMins = (w.endTime! - w.startTime) / 60000.0;
      }
      final autoKcal = Nutrition.estimateStrengthBurnKcal(
        totalVolumeKg: vol,
        workSets: workSets,
        weightKg: weightKg,
        elapsedMinutes: elapsedMins,
      );
      final effectiveKcal = Nutrition.burnForWorkout(
        workout: w,
        totalVolumeKg: vol,
        workSets: workSets,
        weightKg: weightKg,
      );
      out.add(_WorkoutSummary(
        w,
        names,
        primaryCat ?? L10nHelper.cardioOtherCategory,
        workSets,
        vol,
        effectiveKcal,
        autoKcal,
      ));
    }
    WidgetService.sync(force: true);
    if (!mounted) return;
    setState(() {
      _userWeightKg = weightKg;
      _items = out;
      _cardios = cardios;
      _exercises = exercises;
      _inProgress = inProgress;
      _plan = plan;
      _loading = false;
    });
    if (inProgress != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _inProgress == null) return;
        InProgressWorkoutHelper.maybePromptStale(
          context,
          _inProgress!,
          weightKg: _userWeightKg,
          onResume: () => _openSession(_inProgress!.workout.id!),
          onChanged: _load,
        );
      });
    }
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
      final burn = Nutrition.burnForCardio(res, weightKg: _userWeightKg);
      toast(context, context.l10n.workoutCardioSavedToast(fmtNum(burn)));
      _load();
    }
  }

  /// 底部弹窗：手动修正某次力量训练的实际时长与消耗热量
  Future<void> _showAdjustWorkoutSheet(_WorkoutSummary it) async {
    final res = await showModalBottomSheet<({int? durationMin, double? burnKcal, bool reset})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AdjustWorkoutSheet(
        summary: it,
        weightKg: _userWeightKg,
      ),
    );
    if (res == null) return;
    final w = it.workout;
    if (res.reset) {
      w.manualDurationMin = null;
      w.manualBurnKcal = null;
    } else {
      w.manualDurationMin = res.durationMin;
      w.manualBurnKcal = res.burnKcal;
    }
    await Repo.updateWorkout(w);
    if (!mounted) return;
    final updatedBurn = Nutrition.burnForWorkout(
      workout: w,
      totalVolumeKg: it.volume,
      workSets: it.workSets,
      weightKg: _userWeightKg,
    );
    toast(context, context.l10n.workoutAdjustSavedToast(fmtNum(updatedBurn)));
    _load();
  }

  /// 底部弹窗：快速补录一次训练（直接填日期/时长/消耗，不进入计时会话）
  Future<void> _showQuickLogWorkoutSheet() async {
    final res = await showModalBottomSheet<
        ({String date, String note, int durationMin, double burnKcal, Exercise? exercise, int sets})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _QuickLogWorkoutSheet(
        weightKg: _userWeightKg,
        exercises: _exercises,
      ),
    );
    if (res == null) return;
    final d = parseDate(res.date);
    final now = DateTime.now();
    final startDt = DateTime(d.year, d.month, d.day, now.hour, now.minute);
    final startMs = startDt.millisecondsSinceEpoch;
    final endMs = startMs + res.durationMin * 60000;
    final wid = await Repo.createWorkout(Workout(
      date: dateOnlyStr(res.date),
      startTime: startMs,
      endTime: endMs,
      note: res.note.trim().isEmpty ? null : res.note.trim(),
      manualDurationMin: res.durationMin,
      manualBurnKcal: res.burnKcal,
    ));
    if (res.exercise != null && res.exercise!.id != null && res.sets > 0) {
      final rows = [
        for (var i = 1; i <= res.sets.clamp(1, 30); i++)
          WorkoutSet(
            workoutId: wid,
            exerciseId: res.exercise!.id!,
            setIndex: i,
            weight: 0,
            reps: 0,
            isWarmup: false,
          ),
      ];
      await Repo.replaceSets(wid, rows);
    }
    if (!mounted) return;
    toast(
      context,
      context.l10n.workoutQuickLogSavedToast(res.durationMin, fmtNum(res.burnKcal)),
    );
    _load();
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
      if (_inProgress != null) ...[
        InProgressWorkoutCard(
          snapshot: _inProgress!,
          onResume: () => _openSession(_inProgress!.workout.id!),
          onFinish: () async {
            await InProgressWorkoutHelper.finishAndSave(
              context,
              _inProgress!,
              weightKg: _userWeightKg,
            );
            _load();
          },
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (_plan != null) ...[
        _activePlanCard(_plan!),
        const SizedBox(height: AppSpacing.md),
      ],
      if (_items.isNotEmpty) _volumeBarCard(),
      SectionTitle(
        l.workoutHistoryTitle,
        icon: Icons.history_rounded,
        iconColor: workoutColor,
        trailing: TextButton.icon(
          onPressed: _showQuickLogWorkoutSheet,
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: Text(l.workoutQuickLogBtn),
        ),
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

  Future<void> _renamePlan(TrainingPlan plan) async {
    final l = context.l10n;
    final ctrl = TextEditingController(text: plan.planName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.workoutPlanRenameTitle, style: AppTypography.sectionTitle(ctx)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: l.workoutPlanRenameLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: Text(l.commonSave),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nextName == null || nextName == plan.planName) return;
    plan.planName = nextName;
    await Repo.saveTrainingPlan(plan);
    _load();
  }

  Future<void> _confirmDeletePlan(TrainingPlan plan) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.workoutPlanDeleteTitle(plan.planName), style: AppTypography.sectionTitle(ctx)),
        content: Text(l.workoutPlanDeleteDesc, style: AppTypography.body(ctx)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger(ctx),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Repo.clearTrainingPlan();
    if (!mounted) return;
    toast(context, l.workoutPlanDeletedToast);
    _load();
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
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz_rounded, color: AppColors.textSecondary(context)),
                onSelected: (action) async {
                  if (action == 'rename') {
                    await _renamePlan(plan);
                  } else if (action == 'replace') {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AiChatScreen()),
                    );
                    _load();
                  } else if (action == 'delete') {
                    await _confirmDeletePlan(plan);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text(l.workoutPlanMenuRename),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'replace',
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text(l.workoutPlanMenuReplace),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger(ctx)),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          l.workoutPlanMenuDelete,
                          style: TextStyle(color: AppColors.danger(ctx)),
                        ),
                      ],
                    ),
                  ),
                ],
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
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _startNew(),
              icon: const Icon(Icons.bolt_rounded, size: 16),
              label: Text(l.workoutFreeTrainingBtn),
            ),
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
        final effDur = c.effectiveDurationMinutes;
        final effBurn = Nutrition.burnForCardio(c, weightKg: _userWeightKg);
        final warning = AppColors.warning(context);
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${l.workoutCardioItemTitle(typeLabel, fmtNum(effDur))}${c.distanceKm != null ? ' · ${fmtNum(c.distanceKm!, digits: 2)} km' : ''}',
                              style: AppTypography.cardTitle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (c.isManuallyAdjusted) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.softBg(context, warning),
                                borderRadius: AppRadius.bSm,
                              ),
                              child: Text(
                                l.workoutAdjustedBadge,
                                style: AppTypography.badge(context, color: warning)
                                    .copyWith(fontSize: 10),
                              ),
                            ),
                          ],
                        ],
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
                    '-${fmtNum(effBurn)} kcal',
                    style: AppTypography.badge(context, color: cardioColor),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l.workoutAdjustTooltip,
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.textSecondary(context),
                  ),
                  onPressed: () => _addOrEditCardio(c),
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

  /// 最近 7 次训练容量柱状可视化卡片（单条记录自动切换居中单柱，避免铺满整行）
  Widget _volumeBarCard() {
    final l = context.l10n;
    final workoutColor = AppColors.moduleWorkout(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final recent = _items.where((e) => e.volume > 0).take(7).toList().reversed.toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final maxVol = recent.fold<double>(1, (m, e) => e.volume > m ? e.volume : m);

    Widget buildBar(
      _WorkoutSummary it, {
      double? fixedWidth,
    }) {
      final ratio = (it.volume / maxVol).clamp(0.10, 1.0);
      final vis = categoryVisual(it.primaryCategory);
      final barColor = AppColors.adaptForDark(context, vis.color);
      final dateShort =
          it.workout.date.length >= 10 ? it.workout.date.substring(5, 10) : it.workout.date;
      return Column(
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
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (_, h, _) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: fixedWidth ?? 48,
                minWidth: fixedWidth ?? 0,
              ),
              child: Container(
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
          ),
          const SizedBox(height: 6),
          Text(
            dateShort,
            style: AppTypography.caption(context).copyWith(fontSize: 10),
            maxLines: 1,
          ),
        ],
      );
    }

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
          if (recent.length == 1)
            SizedBox(
              height: 118,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  buildBar(recent.first, fixedWidth: 52),
                  const SizedBox(width: AppSpacing.xl),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${fmtNum(recent.first.volume)} kg',
                        style: AppTypography.metricLarge(context, color: workoutColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.workoutSingleDayVolumeSub(
                          L10nHelper.friendlyDateL10n(context, recent.first.workout.date),
                        ),
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 118,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: recent
                    .map(
                      (it) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                          child: Center(child: buildBar(it)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _workoutItemCard(_WorkoutSummary it) {
    final l = context.l10n;
    final w = it.workout;
    final durMin = w.effectiveDurationMinutes;
    final vis = categoryVisual(it.primaryCategory);
    final catColor = AppColors.adaptForDark(context, vis.color);
    final warning = AppColors.warning(context);
    final displayNames =
        it.exerciseNames.map((n) => L10nHelper.exerciseDisplayName(context, n)).toList();
    final titleText = displayNames.isNotEmpty
        ? displayNames.join(' · ')
        : ((w.note != null && w.note!.trim().isNotEmpty)
            ? w.note!.trim()
            : l.workoutEmptySessionTitle);

    final line1Parts = <String>[
      L10nHelper.friendlyDateL10n(context, w.date),
      if (it.workSets > 0) l.workoutCompactSets(it.workSets),
      if (it.volume > 0) '${fmtNum(it.volume)} kg',
    ];
    final line2Parts = <String>[
      if (durMin != null && durMin > 0) l.workoutCompactDuration(durMin),
      if (it.estCalories > 0)
        w.isManuallyAdjusted
            ? l.workoutCompactBurnExact(fmtNum(it.estCalories))
            : l.workoutCompactBurnEst(fmtNum(it.estCalories)),
    ];

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
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle(context),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        line1Parts.join(' · '),
                        style: AppTypography.bodySecondary(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (w.isManuallyAdjusted) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.softBg(context, warning),
                          borderRadius: AppRadius.bSm,
                        ),
                        child: Text(
                          l.workoutAdjustedBadge,
                          style: AppTypography.badge(context, color: warning)
                              .copyWith(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                if (line2Parts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    line2Parts.join(' · '),
                    style: AppTypography.caption(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l.workoutAdjustTooltip,
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppColors.textSecondary(context),
            ),
            onPressed: () => _showAdjustWorkoutSheet(it),
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
    _mins = TextEditingController(
      text: e != null ? fmtNum(e.effectiveDurationMinutes) : '30',
    );
    _dist = TextEditingController(
      text: e?.distanceKm != null ? fmtNum(e!.distanceKm!, digits: 2) : '',
    );
    _kcal = TextEditingController(
      text: e != null ? fmtNum(Nutrition.burnForCardio(e, weightKg: widget.weightKg)) : '',
    );
    if (e?.manualBurnKcal != null && e!.manualBurnKcal! > 0) {
      _manualKcal = true;
    }
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
            final metVal = Nutrition.cardioMets[_type] ?? 5.0;
            final autoKcal = Nutrition.calcMetCalories(
              met: metVal,
              weightKg: widget.weightKg,
              minutes: mins,
            );
            final rawKcal = Nutrition.parsePlainDouble(_kcal.text) ?? autoKcal;
            final kcal = rawKcal.clamp(0.0, Nutrition.maxSingleActivityBurnKcal).toDouble();
            final e = widget.existing;
            final manualBurn = _manualKcal
                ? kcal.clamp(0.0, Nutrition.maxManualWorkoutBurnKcal).toDouble()
                : e?.manualBurnKcal;
            final manualDur = (e != null && (mins - e.durationMinutes).abs() > 0.01)
                ? mins
                : e?.manualDurationMin;
            Navigator.pop(
              context,
              CardioRecord(
                id: e?.id,
                date: dateOnlyStr(_date),
                type: _type,
                durationMinutes: e?.durationMinutes ?? mins,
                distanceKm: dist,
                calories: kcal,
                manualDurationMin: manualDur,
                manualBurnKcal: manualBurn,
                createdAt: e?.createdAt,
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

/// 底部弹窗：手动修正力量训练实际时长与消耗热量
class _AdjustWorkoutSheet extends StatefulWidget {
  final _WorkoutSummary summary;
  final double weightKg;

  const _AdjustWorkoutSheet({
    required this.summary,
    required this.weightKg,
  });

  @override
  State<_AdjustWorkoutSheet> createState() => _AdjustWorkoutSheetState();
}

class _AdjustWorkoutSheetState extends State<_AdjustWorkoutSheet> {
  late final TextEditingController _durCtrl;
  late final TextEditingController _kcalCtrl;
  bool _manualBurnEdited = false;

  @override
  void initState() {
    super.initState();
    final w = widget.summary.workout;
    final initDur = w.effectiveDurationMinutes;
    _durCtrl = TextEditingController(text: (initDur != null && initDur > 0) ? '$initDur' : '');
    _kcalCtrl = TextEditingController(
      text: widget.summary.estCalories > 0 ? fmtNum(widget.summary.estCalories) : '',
    );
    _manualBurnEdited = w.manualBurnKcal != null && w.manualBurnKcal! > 0;
  }

  @override
  void dispose() {
    _durCtrl.dispose();
    _kcalCtrl.dispose();
    super.dispose();
  }

  void _onDurationChanged(String _) {
    if (_manualBurnEdited) return;
    final dur = Nutrition.parsePlainInt(_durCtrl.text);
    if (dur != null && dur > 0) {
      final est = Nutrition.calcMetCalories(
        met: Nutrition.strengthMet,
        weightKg: widget.weightKg,
        minutes: dur.toDouble().clamp(1.0, 600.0),
      ).clamp(0.0, Nutrition.maxManualWorkoutBurnKcal);
      _kcalCtrl.text = fmtNum(est);
    } else {
      _kcalCtrl.text = fmtNum(widget.summary.autoCalories);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final workoutColor = AppColors.moduleWorkout(context);
    final info = AppColors.info(context);
    final danger = AppColors.danger(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        bottomInset + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, workoutColor),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(Icons.edit_rounded, color: workoutColor, size: 19),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(l.workoutAdjustTitle, style: AppTypography.sectionTitle(context)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _durCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              onChanged: _onDurationChanged,
              decoration: InputDecoration(
                labelText: l.workoutAdjustDurationLabel,
                suffixText: l.workoutAdjustDurationUnit,
                prefixIcon: Icon(Icons.timer_rounded, color: workoutColor),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _kcalCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => _manualBurnEdited = true,
              decoration: InputDecoration(
                labelText: l.workoutAdjustBurnLabel,
                suffixText: 'kcal',
                prefixIcon: Icon(Icons.local_fire_department_rounded, color: danger),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: info),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.workoutAdjustHint(fmtNum(widget.summary.autoCalories)),
                    style: AppTypography.caption(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (widget.summary.workout.isManuallyAdjusted)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      (durationMin: null, burnKcal: null, reset: true),
                    ),
                    child: Text(l.workoutAdjustResetBtn),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.commonCancel),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () {
                    final parsedDur = Nutrition.parsePlainInt(_durCtrl.text);
                    final safeDur = (parsedDur != null && parsedDur > 0)
                        ? parsedDur.clamp(1, 600)
                        : null;
                    final parsedKcal = Nutrition.parsePlainDouble(_kcalCtrl.text);
                    final safeKcal = (_manualBurnEdited && parsedKcal != null && parsedKcal > 0)
                        ? parsedKcal.clamp(1.0, Nutrition.maxManualWorkoutBurnKcal).toDouble()
                        : null;
                    Navigator.pop(
                      context,
                      (durationMin: safeDur, burnKcal: safeKcal, reset: false),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(l.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部弹窗：快速补录一次训练（选日期、填时长、填消耗、可选备注与关联动作组数）
class _QuickLogWorkoutSheet extends StatefulWidget {
  final double weightKg;
  final List<Exercise> exercises;

  const _QuickLogWorkoutSheet({
    required this.weightKg,
    required this.exercises,
  });

  @override
  State<_QuickLogWorkoutSheet> createState() => _QuickLogWorkoutSheetState();
}

class _QuickLogWorkoutSheetState extends State<_QuickLogWorkoutSheet> {
  String _date = today();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _durCtrl = TextEditingController(text: '45');
  final TextEditingController _kcalCtrl = TextEditingController();
  final TextEditingController _setsCtrl = TextEditingController();
  Exercise? _selectedExercise;
  bool _manualKcal = false;

  @override
  void initState() {
    super.initState();
    _recalc();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _durCtrl.dispose();
    _kcalCtrl.dispose();
    _setsCtrl.dispose();
    super.dispose();
  }

  void _recalc() {
    if (_manualKcal) return;
    final mins = Nutrition.parsePlainInt(_durCtrl.text) ?? 0;
    final kcal = Nutrition.calcMetCalories(
      met: Nutrition.strengthMet,
      weightKg: widget.weightKg,
      minutes: mins.toDouble().clamp(0.0, 600.0),
    ).clamp(0.0, Nutrition.maxManualWorkoutBurnKcal);
    _kcalCtrl.text = mins > 0 ? fmtNum(kcal) : '';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final workoutColor = AppColors.moduleWorkout(context);
    final teal = AppColors.teal(context);
    final danger = AppColors.danger(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        bottomInset + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, workoutColor),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(Icons.edit_note_rounded, color: workoutColor, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(l.workoutQuickLogTitle, style: AppTypography.sectionTitle(context)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
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
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: l.workoutQuickLogNoteLabel,
                prefixIcon: Icon(Icons.notes_rounded, color: workoutColor),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _durCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    onChanged: (_) => setState(_recalc),
                    decoration: InputDecoration(
                      labelText: l.workoutAdjustDurationLabel,
                      suffixText: l.workoutAdjustDurationUnit,
                      prefixIcon: Icon(Icons.timer_rounded, color: workoutColor),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _kcalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (_) => _manualKcal = true,
                    decoration: InputDecoration(
                      labelText: l.workoutAdjustBurnLabel,
                      suffixText: 'kcal',
                      prefixIcon: Icon(Icons.local_fire_department_rounded, color: danger),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.exercises.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<Exercise?>(
                      initialValue: _selectedExercise,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l.workoutQuickLogExerciseLabel,
                      ),
                      items: [
                        DropdownMenuItem<Exercise?>(
                          value: null,
                          child: Text(l.workoutQuickLogNone),
                        ),
                        ...widget.exercises.map(
                          (ex) => DropdownMenuItem<Exercise?>(
                            value: ex,
                            child: Text(
                              L10nHelper.exerciseDisplayName(context, ex.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedExercise = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _setsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: InputDecoration(
                        labelText: l.workoutQuickLogSetsLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.commonCancel),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () {
                    final dur = Nutrition.parsePlainInt(_durCtrl.text) ?? 0;
                    if (dur <= 0) {
                      toast(context, l.workoutQuickLogDurationRequired);
                      return;
                    }
                    final safeDur = dur.clamp(1, 600);
                    final autoKcal = Nutrition.calcMetCalories(
                      met: Nutrition.strengthMet,
                      weightKg: widget.weightKg,
                      minutes: safeDur.toDouble(),
                    );
                    final parsedKcal = Nutrition.parsePlainDouble(_kcalCtrl.text) ?? autoKcal;
                    final safeKcal =
                        parsedKcal.clamp(1.0, Nutrition.maxManualWorkoutBurnKcal).toDouble();
                    final setsCount = (Nutrition.parsePlainInt(_setsCtrl.text) ?? 0).clamp(0, 30);
                    final noteText = _noteCtrl.text.trim().isNotEmpty
                        ? _noteCtrl.text.trim()
                        : (_selectedExercise == null ? l.workoutQuickLogNoteDefault : '');
                    Navigator.pop(
                      context,
                      (
                        date: _date,
                        note: noteText,
                        durationMin: safeDur,
                        burnKcal: safeKcal,
                        exercise: _selectedExercise,
                        sets: setsCount,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(l.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
