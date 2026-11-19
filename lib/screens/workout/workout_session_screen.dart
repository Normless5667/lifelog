import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/battery_probe_service.dart';
import '../../services/nutrition.dart';
import '../../services/reminder_service.dart';
import '../../services/usage_telemetry_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'exercise_library_screen.dart';

/// 单次训练会话（v2.0）：
/// - 计时采用绝对时间戳差值计算，退后台或被新页面遮挡时自动停止 UI Timer（省电），回前台自动对齐时间
/// - 顶部秒表、训练统计与休息倒计时均拆分为 ValueListenableBuilder 局部刷新，输入数字时不触发整页重建
class WorkoutSessionScreen extends StatefulWidget {
  final int workoutId;
  final bool isNew;
  final List<TrainingPlanExercise>? initialPlanExercises;

  @visibleForTesting
  final Workout? initialWorkoutForTest;

  @visibleForTesting
  final List<({Exercise exercise, List<WorkoutSet> sets})>? initialBlocksForTest;

  const WorkoutSessionScreen({
    super.key,
    required this.workoutId,
    this.isNew = false,
    this.initialPlanExercises,
    this.initialWorkoutForTest,
    this.initialBlocksForTest,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _SetRow {
  final Key rowKey = UniqueKey();
  final TextEditingController weight;
  final TextEditingController reps;
  final FocusNode weightFocus = FocusNode();
  final FocusNode repsFocus = FocusNode();
  bool warmup;
  bool done;
  int? completedAtMs;

  _SetRow({double w = 0, int r = 0, this.warmup = false, this.done = false})
      : weight = TextEditingController(text: w <= 0 ? '' : fmtNum(w, digits: 1)),
        reps = TextEditingController(text: r <= 0 ? '' : '$r');

  void dispose() {
    weight.dispose();
    reps.dispose();
    weightFocus.dispose();
    repsFocus.dispose();
  }
}

class _ExerciseBlock {
  final Exercise exercise;
  final List<_SetRow> sets;
  final List<WorkoutSet> lastWorkSets;
  final TrainingPlanExercise? planExercise;

  _ExerciseBlock(
    this.exercise,
    this.sets,
    this.lastWorkSets, {
    this.planExercise,
  });
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen>
    with WidgetsBindingObserver, RouteAware {
  static const _timerTag = 'workout_session';
  Workout? _workout;
  final List<_ExerciseBlock> _blocks = [];
  bool _loading = true;
  double _userWeightKg = 65;

  Timer? _ticker;
  bool _routeVisible = true;
  bool _appInForeground = true;
  final ValueNotifier<int> _elapsedNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _restRemainingNotifier = ValueNotifier<int>(0);
  final ValueNotifier<({int sets, double volume, double kcal})> _statsNotifier =
      ValueNotifier((sets: 0, volume: 0.0, kcal: 0.0));
  int _restTargetSeconds = 90;
  int? _restEndAtMs;
  bool _restPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ReminderService.setKeepScreenOn(true);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      BatteryProbeService.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BatteryProbeService.routeObserver.unsubscribe(this);
    _stopTicker();
    _elapsedNotifier.dispose();
    _restRemainingNotifier.dispose();
    _statsNotifier.dispose();
    ReminderService.cancelRestAlarm();
    ReminderService.setKeepScreenOn(false);
    for (final b in _blocks) {
      for (final s in b.sets) {
        s.dispose();
      }
    }
    super.dispose();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _stopTicker();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncTimeFromWallClock();
    _ensureTickerIfVisible();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _appInForeground = false;
      _stopTicker();
    } else if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _syncTimeFromWallClock();
      _ensureTickerIfVisible();
    }
  }

  void _syncTimeFromWallClock() {
    final w = _workout;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (w != null) {
      if (w.endTime != null && !widget.isNew) {
        _elapsedNotifier.value = ((w.endTime! - w.startTime) ~/ 1000).clamp(0, 86400);
      } else {
        _elapsedNotifier.value = ((nowMs - w.startTime) ~/ 1000).clamp(0, 86400);
      }
    }
    if (!_restPaused && _restEndAtMs != null) {
      final rem = ((_restEndAtMs! - nowMs) / 1000).ceil();
      if (rem <= 0) {
        _restEndAtMs = null;
        if (_restRemainingNotifier.value > 0) {
          _restRemainingNotifier.value = 0;
          if (mounted) {
            ReminderService.vibrateShort();
            toast(context, context.l10n.sessionRestFinishedToast);
          }
        }
      } else {
        _restRemainingNotifier.value = rem;
      }
    }
  }

  void _ensureTickerIfVisible() {
    if (!_routeVisible || !_appInForeground || _ticker != null) return;
    BatteryProbeService.instance.onTimerStarted(_timerTag);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncTimeFromWallClock();
    });
  }

  void _stopTicker() {
    if (_ticker != null) {
      _ticker?.cancel();
      _ticker = null;
      BatteryProbeService.instance.onTimerStopped(_timerTag);
    }
  }

  Future<void> _load() async {
    if (widget.initialWorkoutForTest != null) {
      _workout = widget.initialWorkoutForTest;
      for (final item in widget.initialBlocksForTest ?? const <({Exercise exercise, List<WorkoutSet> sets})>[]) {
        _blocks.add(_ExerciseBlock(
          item.exercise,
          item.sets
              .map((s) => _SetRow(w: s.weight, r: s.reps, warmup: s.isWarmup, done: false))
              .toList(),
          const [],
        ));
      }
      _syncTimeFromWallClock();
      _refreshLiveStats();
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
    }

    final w = await Repo.getWorkout(widget.workoutId);
    final rec = await Repo.latestBodyRecordWithWeight();
    _userWeightKg = Nutrition.sanitizeWeightKg(rec?.weight) ?? 65;
    final sets = await Repo.getSets(widget.workoutId);
    final exMap = {for (final e in await Repo.getExercises()) e.id!: e};
    final byEx = <int, List<WorkoutSet>>{};
    for (final s in sets) {
      byEx.putIfAbsent(s.exerciseId, () => []).add(s);
    }
    for (final entry in byEx.entries) {
      final ex = exMap[entry.key] ??
          Exercise(id: entry.key, name: 'Exercise', category: L10nHelper.cardioOtherCategory);
      final lastSets = await Repo.lastSetsForExercise(ex.id!, excludeWorkoutId: widget.workoutId);
      final lastWork = lastSets.where((s) => !s.isWarmup).toList();
      _blocks.add(_ExerciseBlock(
        ex,
        entry.value
            .map((s) => _SetRow(w: s.weight, r: s.reps, warmup: s.isWarmup, done: true))
            .toList(),
        lastWork,
      ));
    }

    if (_blocks.isEmpty && widget.initialPlanExercises != null) {
      for (final pe in widget.initialPlanExercises!) {
        final ex = await Repo.findOrCreateExercise(pe.name);
        final lastSets = await Repo.lastSetsForExercise(ex.id!, excludeWorkoutId: widget.workoutId);
        final lastWork = lastSets.where((s) => !s.isWarmup).toList();
        final hintWeight =
            double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(pe.weightHint)?.group(0) ?? '');
        final hintReps = int.tryParse(RegExp(r'\d+').firstMatch(pe.reps)?.group(0) ?? '') ?? 10;
        final defW = hintWeight ?? (lastWork.isEmpty ? 0.0 : lastWork.first.weight);
        final defR = lastWork.isEmpty ? hintReps : lastWork.first.reps;
        final rows = [for (var i = 0; i < pe.sets.clamp(1, 10); i++) _SetRow(w: defW, r: defR)];
        _blocks.add(_ExerciseBlock(
          ex,
          rows,
          lastWork,
          planExercise: pe,
        ));
      }
    }

    _workout = w;
    _syncTimeFromWallClock();
    _ensureTickerIfVisible();
    _refreshLiveStats();

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  String _fmtClock(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _startRestTimer({int? seconds, String? exerciseName}) {
    final dur = (seconds ?? _restTargetSeconds).clamp(5, 3600);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    _restPaused = false;
    _restEndAtMs = DateTime.now().millisecondsSinceEpoch + dur * 1000;
    _restRemainingNotifier.value = dur;
    ReminderService.cancelRestAlarm();
    ReminderService.scheduleRestAlarm(
      dur,
      nextHint: exerciseName,
    );
  }

  void _stopRestTimer() {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    _restPaused = false;
    _restEndAtMs = null;
    _restRemainingNotifier.value = 0;
    ReminderService.cancelRestAlarm();
  }

  String _formatLast(BuildContext context, Exercise ex, List<WorkoutSet> work) {
    if (work.isEmpty) return '';
    final l = context.l10n;
    if (L10nHelper.isCardioCategory(ex.category)) {
      final recs = work
          .map((s) =>
              '${fmtNum(s.weight)} ${l.sessionCardioMins}${s.reps > 0 ? ' · ${s.reps} ${l.sessionCardioStepsUnit}' : ''}')
          .join('  ');
      return l.sessionLastCardioHint(recs);
    }
    final recs = work.map((s) => '${fmtNum(s.weight, digits: 1)}kg×${s.reps}').join('  ');
    return l.sessionLastStrengthHint(recs);
  }

  Future<void> _addExercise() async {
    final ex = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen(selectMode: true)),
    );
    if (ex == null) return;
    final lastSets = await Repo.lastSetsForExercise(ex.id!, excludeWorkoutId: widget.workoutId);
    final lastWork = lastSets.where((s) => !s.isWarmup).toList();
    final isCardio = L10nHelper.isCardioCategory(ex.category);
    final defW = lastWork.isEmpty ? (isCardio ? 30.0 : 0.0) : lastWork.first.weight;
    final defR = lastWork.isEmpty ? 0 : lastWork.first.reps;
    if (!mounted) return;
    setState(() {
      _blocks.add(_ExerciseBlock(ex, [_SetRow(w: defW, r: defR)], lastWork));
    });
    _refreshLiveStats();
  }

  void _addSet(_ExerciseBlock b) {
    final isCardio = L10nHelper.isCardioCategory(b.exercise.category);
    final prev = b.sets.isEmpty ? null : b.sets.last;
    final parsedW = Nutrition.parsePlainDouble(prev?.weight.text ?? '') ?? 0;
    final parsedR = Nutrition.parsePlainInt(prev?.reps.text ?? '') ?? 0;
    final copyW = isCardio
        ? (parsedW <= 1440 ? parsedW : 0.0)
        : (parsedW <= Nutrition.maxSetWeightKg ? parsedW : 0.0);
    final copyR = isCardio
        ? (parsedR <= 200000 ? parsedR : 0)
        : (parsedR <= Nutrition.maxSetReps ? parsedR : 0);
    setState(() {
      b.sets.add(_SetRow(w: copyW, r: copyR, warmup: false, done: false));
    });
    _refreshLiveStats();
  }

  void _removeBlock(int bi) {
    final removed = _blocks[bi];
    setState(() {
      _blocks.removeAt(bi);
    });
    for (final s in removed.sets) {
      s.dispose();
    }
    _refreshLiveStats();
  }

  void _removeSet(_ExerciseBlock b, int si) {
    final removed = b.sets[si];
    setState(() {
      b.sets.removeAt(si);
    });
    removed.dispose();
    _refreshLiveStats();
  }

  void _refreshLiveStats() {
    _statsNotifier.value = _liveStats();
  }

  ({int sets, double volume, double kcal}) _liveStats() {
    final rows = <({double weight, int reps, bool isWarmup})>[];
    for (final b in _blocks) {
      if (L10nHelper.isCardioCategory(b.exercise.category)) continue;
      for (final s in b.sets) {
        final w = Nutrition.parsePlainDouble(s.weight.text) ?? 0;
        final r = Nutrition.parsePlainInt(s.reps.text) ?? 0;
        rows.add((weight: w, reps: r, isWarmup: s.warmup));
      }
    }
    final strength = Nutrition.calcStrengthStats(rows);
    final elapsedMins = (_elapsedNotifier.value / 60.0).clamp(0.0, 180.0);
    final wk = _workout;
    final kcal = wk != null
        ? Nutrition.burnForWorkout(
            workout: wk,
            totalVolumeKg: strength.volume,
            workSets: strength.sets,
            weightKg: _userWeightKg,
            overrideElapsedMinutes: elapsedMins,
          )
        : Nutrition.estimateStrengthBurnKcal(
            totalVolumeKg: strength.volume,
            workSets: strength.sets,
            weightKg: _userWeightKg,
            elapsedMinutes: elapsedMins,
          );
    return (sets: strength.sets, volume: strength.volume, kcal: kcal);
  }

  Future<void> _finish() async {
    final w = _workout;
    if (w == null) return;
    _stopTicker();
    ReminderService.cancelRestAlarm();
    final allSets = <WorkoutSet>[];
    for (final b in _blocks) {
      final isCardio = L10nHelper.isCardioCategory(b.exercise.category);
      var idx = 1;
      for (final s in b.sets) {
        final rawW = Nutrition.parsePlainDouble(s.weight.text) ?? 0;
        final rawR = Nutrition.parsePlainInt(s.reps.text) ?? 0;
        final weight = isCardio
            ? rawW.clamp(0.0, 1440.0).toDouble()
            : (rawW <= Nutrition.maxSetWeightKg ? rawW : 0.0);
        final reps = isCardio
            ? rawR.clamp(0, 200000)
            : (rawR <= Nutrition.maxSetReps ? rawR : 0);
        if (isCardio) {
          if (weight <= 0 && reps <= 0) continue;
        } else {
          if (weight <= 0 || reps <= 0) continue;
        }
        allSets.add(WorkoutSet(
          workoutId: w.id!,
          exerciseId: b.exercise.id!,
          setIndex: idx++,
          weight: weight,
          reps: reps,
          isWarmup: s.warmup,
        ));
      }
    }
    if (allSets.isEmpty && widget.isNew) {
      UsageTelemetryService.instance.trackFeature(
        'start_workout',
        'cancel',
        durationMs: _elapsedNotifier.value * 1000,
      );
      await Repo.deleteWorkout(w.id!);
      if (mounted) Navigator.pop(context);
      return;
    }
    final elapsedSecs = _elapsedNotifier.value;
    UsageTelemetryService.instance.trackFeature(
      'start_workout',
      'success',
      durationMs: elapsedSecs * 1000,
    );
    w.date = dateOnlyStr(w.date);
    w.endTime = w.startTime + (elapsedSecs * 1000);
    await Repo.updateWorkout(w);
    await Repo.replaceSets(w.id!, allSets);
    if (!mounted) return;
    final stats = _liveStats();
    toast(
      context,
      context.l10n.sessionFinishedToast(
        elapsedSecs ~/ 60,
        stats.sets,
        fmtNum(stats.volume),
        fmtNum(stats.kcal),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const numKb = TextInputType.numberWithOptions(decimal: true);
    final workoutColor = AppColors.moduleWorkout(context);
    final kbBottom = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: AppSpacing.xs + 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, workoutColor, lightAlpha: 0.12, darkAlpha: 0.20),
                  borderRadius: AppRadius.bPill,
                  border: Border.all(color: AppColors.softBorder(context, workoutColor)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_rounded, size: 15, color: workoutColor),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<int>(
                      valueListenable: _elapsedNotifier,
                      builder: (ctx, secs, _) => Text(
                        _fmtClock(secs),
                        style: AppTypography.metricMedium(ctx, color: workoutColor)
                            .copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ValueListenableBuilder<({int sets, double volume, double kcal})>(
                  valueListenable: _statsNotifier,
                  builder: (ctx, stats, _) => Text(
                    l.sessionHeaderStats(stats.sets, fmtNum(stats.volume)),
                    style: AppTypography.bodySecondary(ctx),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.icon(
                onPressed: _finish,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary(context),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 17),
                label: Text(l.sessionFinishBtn),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addExercise,
          elevation: 2,
          backgroundColor: workoutColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.bLg),
          icon: const Icon(Icons.add_rounded),
          label: Text(
            l.sessionAddExerciseBtn,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _restTimerBanner(),
                  Expanded(
                    child: _blocks.isEmpty
                        ? Center(
                            child: EmptyHint(
                              icon: Icons.fitness_center_rounded,
                              text: l.sessionEmptyHint,
                              actionLabel: l.sessionSelectExerciseBtn,
                              onAction: _addExercise,
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.md,
                              AppSpacing.lg,
                              kbBottom + 96,
                            ),
                            itemCount: _blocks.length,
                            itemBuilder: (_, bi) => _buildExerciseCard(bi, numKb),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 顶部组间休息计时器横幅（仅用 ValueListenableBuilder 局部更新倒计时，不重绘下方列表）
  Widget _restTimerBanner() {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final teal = AppColors.teal(context);

    return ValueListenableBuilder<int>(
      valueListenable: _restRemainingNotifier,
      builder: (context, restRem, _) {
        final active = restRem > 0;
        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: active
                ? AppColors.softBg(context, primary, lightAlpha: 0.12, darkAlpha: 0.20)
                : AppColors.surface(context),
            borderRadius: AppRadius.bLg,
            border: Border.all(
              color: active ? AppColors.softBorder(context, primary) : AppColors.border(context),
            ),
            boxShadow: AppShadows.subtle(context),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, active ? primary : teal),
                  borderRadius: AppRadius.bSm,
                ),
                child: Icon(
                  active ? Icons.hourglass_top_rounded : Icons.self_improvement_rounded,
                  color: active ? primary : teal,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (active) ...[
                Expanded(
                  child: Text(
                    l.sessionRestActive(
                      _fmtClock(restRem),
                      _restPaused ? l.sessionRestPausedTag : '',
                    ),
                    style: AppTypography.metricMedium(context, color: primary),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _restPaused ? l.sessionRestResume : l.sessionRestPause,
                  icon: Icon(
                    _restPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: primary,
                  ),
                  onPressed: () {
                    setState(() => _restPaused = !_restPaused);
                    if (_restPaused) {
                      _restEndAtMs = null;
                      ReminderService.cancelRestAlarm();
                    } else {
                      _restEndAtMs = DateTime.now().millisecondsSinceEpoch + restRem * 1000;
                      ReminderService.scheduleRestAlarm(restRem);
                    }
                  },
                ),
                TextButton(
                  onPressed: () => _startRestTimer(seconds: restRem + 15),
                  child: const Text('+15s'),
                ),
                TextButton(
                  onPressed: _stopRestTimer,
                  child: Text(l.sessionRestSkip),
                ),
              ] else ...[
                Text(l.sessionRestDurationLabel, style: AppTypography.caption(context)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final sec in [60, 90, 120, 180])
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.xs + 2),
                            child: ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppColors.surfaceSubtle(context),
                              selectedColor: AppColors.softBg(context, primary),
                              side: BorderSide(
                                color: _restTargetSeconds == sec
                                    ? AppColors.softBorder(context, primary)
                                    : AppColors.border(context),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: AppRadius.bSm),
                              label: Text(
                                '${sec}s',
                                style: AppTypography.badge(
                                  context,
                                  color: _restTargetSeconds == sec
                                      ? primary
                                      : AppColors.textSecondary(context),
                                ),
                              ),
                              selected: _restTargetSeconds == sec,
                              onSelected: (_) => setState(() => _restTargetSeconds = sec),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l.sessionRestStartNow,
                  icon: Icon(Icons.play_circle_fill_rounded, color: teal, size: 26),
                  onPressed: () => _startRestTimer(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildExerciseCard(int bi, TextInputType numKb) {
    final l = context.l10n;
    final b = _blocks[bi];
    final isCardio = L10nHelper.isCardioCategory(b.exercise.category);
    final vis = categoryVisual(b.exercise.category);
    final catColor = AppColors.adaptForDark(context, vis.color);
    final teal = AppColors.teal(context);
    final warning = AppColors.warning(context);
    final workoutColor = AppColors.moduleWorkout(context);
    final info = AppColors.info(context);
    final success = AppColors.success(context);

    final lastHint = _formatLast(context, b.exercise, b.lastWorkSets);
    final pe = b.planExercise;
    final planHint = pe == null
        ? null
        : l.sessionPlanTargetHint(
            pe.sets,
            pe.reps,
            pe.weightHint.isNotEmpty ? ' (${pe.weightHint})' : '',
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SurfaceCard(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, catColor),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(vis.icon, color: catColor, size: 19),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    L10nHelper.exerciseDisplayName(context, b.exercise.name),
                    style: AppTypography.cardTitle(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, catColor),
                    borderRadius: AppRadius.bPill,
                  ),
                  child: Text(
                    L10nHelper.exerciseCategoryLabel(context, b.exercise.category),
                    style: AppTypography.badge(context, color: catColor),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 19, color: AppColors.textTertiary(context)),
                  onPressed: () => _removeBlock(bi),
                ),
              ],
            ),
            if (planHint != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs + 2),
                child: Text(
                  planHint,
                  style: AppTypography.badge(context, color: teal).copyWith(fontSize: 12),
                ),
              ),
            if (lastHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs + 2, bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 14, color: teal),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(lastHint, style: AppTypography.caption(context)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            for (var si = 0; si < b.sets.length; si++)
              KeyedSubtree(
                key: b.sets[si].rowKey,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      if (!isCardio) ...[
                        InkWell(
                          onTap: () {
                            setState(() => b.sets[si].warmup = !b.sets[si].warmup);
                            _refreshLiveStats();
                          },
                          borderRadius: AppRadius.bSm,
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: b.sets[si].warmup
                                  ? AppColors.softBg(context, warning, lightAlpha: 0.16, darkAlpha: 0.24)
                                  : AppColors.surfaceSubtle(context),
                              borderRadius: AppRadius.bSm,
                              border: Border.all(
                                color: b.sets[si].warmup
                                    ? AppColors.softBorder(context, warning)
                                    : AppColors.border(context),
                              ),
                            ),
                            child: Text(
                              b.sets[si].warmup ? l.sessionWarmupTag : '${si + 1}',
                              style: AppTypography.badge(
                                context,
                                color: b.sets[si].warmup ? warning : AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                      ],
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => b.sets[si].weightFocus.requestFocus(),
                          child: TextField(
                            controller: b.sets[si].weight,
                            focusNode: b.sets[si].weightFocus,
                            keyboardType: numKb,
                            scrollPadding: const EdgeInsets.only(bottom: 120),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: AppTypography.metricMedium(context).copyWith(fontSize: 14),
                            onChanged: (_) => _refreshLiveStats(),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: isCardio ? l.sessionCardioDuration : l.sessionStrengthWeight,
                              suffixText: isCardio ? l.sessionCardioMins : 'kg',
                              prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              prefixIcon: Icon(
                                isCardio ? Icons.timer_rounded : Icons.fitness_center_rounded,
                                size: 16,
                                color: workoutColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs + 2),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => b.sets[si].repsFocus.requestFocus(),
                          child: TextField(
                            controller: b.sets[si].reps,
                            focusNode: b.sets[si].repsFocus,
                            keyboardType: TextInputType.number,
                            scrollPadding: const EdgeInsets.only(bottom: 120),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(isCardio ? 6 : 3),
                            ],
                            style: AppTypography.metricMedium(context).copyWith(fontSize: 14),
                            onChanged: (_) => _refreshLiveStats(),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: isCardio ? l.sessionCardioSteps : l.sessionStrengthReps,
                              suffixText:
                                  isCardio ? l.sessionCardioStepsUnit : l.sessionStrengthRepsUnit,
                              prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              prefixIcon: Icon(
                                isCardio ? Icons.directions_walk_rounded : Icons.repeat_rounded,
                                size: 16,
                                color: info,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!isCardio)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: l.sessionCompleteSetTooltip,
                          icon: Icon(
                            b.sets[si].done
                                ? Icons.check_circle_rounded
                                : Icons.check_circle_outline_rounded,
                            color: b.sets[si].done ? success : AppColors.textTertiary(context),
                          ),
                          onPressed: () {
                            setState(() {
                              b.sets[si].done = !b.sets[si].done;
                              if (b.sets[si].done) {
                                b.sets[si].completedAtMs = DateTime.now().millisecondsSinceEpoch;
                                _startRestTimer(
                                  exerciseName: L10nHelper.exerciseDisplayName(
                                    context,
                                    b.exercise.name,
                                  ),
                                );
                              }
                            });
                          },
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 18,
                          color: AppColors.textTertiary(context),
                        ),
                        onPressed: () => _removeSet(b, si),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addSet(b),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                label: Text(isCardio ? l.sessionAddCardioRow : l.sessionAddStrengthRow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
