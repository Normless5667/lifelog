import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/battery_probe_service.dart';
import '../../services/nutrition.dart';
import '../../services/reminder_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'exercise_library_screen.dart';

/// 单次训练会话：
/// - 计时采用绝对时间戳差值计算，退后台或被新页面遮挡时自动停止 UI Timer（省电），回前台自动对齐时间
/// - 顶部秒表拆分为 ValueListenableBuilder 局部刷新，不触发整页 TextField 重建
class WorkoutSessionScreen extends StatefulWidget {
  final int workoutId;
  final bool isNew;
  final List<TrainingPlanExercise>? initialPlanExercises;

  const WorkoutSessionScreen({
    super.key,
    required this.workoutId,
    this.isNew = false,
    this.initialPlanExercises,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _SetRow {
  final TextEditingController weight;
  final TextEditingController reps;
  bool warmup;
  bool done;
  int? completedAtMs;

  _SetRow({double w = 0, int r = 0, this.warmup = false, this.done = false})
      : weight = TextEditingController(text: w == 0 ? '' : fmtNum(w, digits: 1)),
        reps = TextEditingController(text: r == 0 ? '' : '$r');

  void dispose() {
    weight.dispose();
    reps.dispose();
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
    final w = await Repo.getWorkout(widget.workoutId);
    final rec = await Repo.latestBodyRecordWithWeight();
    _userWeightKg = rec?.weight ?? 65;
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
        entry.value.map((s) => _SetRow(w: s.weight, r: s.reps, warmup: s.isWarmup, done: true)).toList(),
        lastWork,
      ));
    }

    if (_blocks.isEmpty && widget.initialPlanExercises != null) {
      for (final pe in widget.initialPlanExercises!) {
        final ex = await Repo.findOrCreateExercise(pe.name);
        final lastSets = await Repo.lastSetsForExercise(ex.id!, excludeWorkoutId: widget.workoutId);
        final lastWork = lastSets.where((s) => !s.isWarmup).toList();
        final hintWeight = double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(pe.weightHint)?.group(0) ?? '');
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
    final dur = seconds ?? _restTargetSeconds;
    _restPaused = false;
    _restEndAtMs = DateTime.now().millisecondsSinceEpoch + dur * 1000;
    _restRemainingNotifier.value = dur;
    ReminderService.scheduleRestAlarm(
      dur,
      nextHint: exerciseName,
    );
  }

  void _stopRestTimer() {
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
          .map((s) => '${fmtNum(s.weight)} ${l.sessionCardioMins}${s.reps > 0 ? ' · ${s.reps} ${l.sessionCardioStepsUnit}' : ''}')
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
  }

  void _addSet(_ExerciseBlock b) {
    final prev = b.sets.isEmpty ? null : b.sets.last;
    setState(() {
      b.sets.add(_SetRow(
        w: double.tryParse(prev?.weight.text ?? '') ?? 0,
        r: int.tryParse(prev?.reps.text ?? '') ?? 0,
      ));
    });
  }

  ({int sets, double volume, double kcal}) _liveStats() {
    var workSets = 0;
    var vol = 0.0;
    for (final b in _blocks) {
      if (L10nHelper.isCardioCategory(b.exercise.category)) continue;
      for (final s in b.sets) {
        final w = double.tryParse(s.weight.text) ?? 0;
        final r = int.tryParse(s.reps.text) ?? 0;
        if (!s.warmup && (w > 0 || r > 0)) {
          workSets++;
          vol += w * r;
        }
      }
    }
    final mins = (_elapsedNotifier.value / 60.0).clamp(1.0, 180.0);
    final kcal = Nutrition.calcMetCalories(met: Nutrition.strengthMet, weightKg: _userWeightKg, minutes: mins);
    return (sets: workSets, volume: vol, kcal: kcal);
  }

  Future<void> _finish() async {
    final w = _workout;
    if (w == null) return;
    _stopTicker();
    ReminderService.cancelRestAlarm();
    final allSets = <WorkoutSet>[];
    for (final b in _blocks) {
      var idx = 1;
      for (final s in b.sets) {
        final weight = double.tryParse(s.weight.text) ?? 0;
        final reps = int.tryParse(s.reps.text) ?? 0;
        if (weight <= 0 && reps <= 0) continue;
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
      await Repo.deleteWorkout(w.id!);
      if (mounted) Navigator.pop(context);
      return;
    }
    final elapsedSecs = _elapsedNotifier.value;
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
    final stats = _liveStats();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_rounded, size: 16, color: Color(0xFFEF5350)),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<int>(
                      valueListenable: _elapsedNotifier,
                      builder: (_, secs, _) => Text(
                        _fmtClock(secs),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFFEF5350),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.sessionHeaderStats(stats.sets, fmtNum(stats.volume)),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(l.sessionFinishBtn),
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addExercise,
          icon: const Icon(Icons.add_rounded),
          label: Text(l.sessionAddExerciseBtn),
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
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
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
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: _restRemainingNotifier,
      builder: (context, restRem, _) {
        final active = restRem > 0;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(
                active ? Icons.hourglass_top_rounded : Icons.self_improvement_rounded,
                color: active ? cs.primary : cs.outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              if (active) ...[
                Expanded(
                  child: Text(
                    l.sessionRestActive(
                      _fmtClock(restRem),
                      _restPaused ? l.sessionRestPausedTag : '',
                    ),
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _restPaused ? l.sessionRestResume : l.sessionRestPause,
                  icon: Icon(_restPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
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
                Text(l.sessionRestDurationLabel, style: const TextStyle(fontSize: 12)),
                for (final sec in [60, 90, 120, 180])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${sec}s', style: const TextStyle(fontSize: 11)),
                      selected: _restTargetSeconds == sec,
                      onSelected: (_) => setState(() => _restTargetSeconds = sec),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l.sessionRestStartNow,
                  icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.teal),
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
    final lastHint = _formatLast(context, b.exercise, b.lastWorkSets);
    final pe = b.planExercise;
    final planHint = pe == null
        ? null
        : l.sessionPlanTargetHint(
            pe.sets,
            pe.reps,
            pe.weightHint.isNotEmpty ? ' (${pe.weightHint})' : '',
          );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: vis.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(vis.icon, color: vis.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    L10nHelper.exerciseDisplayName(context, b.exercise.name),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: vis.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    L10nHelper.exerciseCategoryLabel(context, b.exercise.category),
                    style: TextStyle(fontSize: 11, color: vis.color, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => setState(() => _blocks.removeAt(bi)),
                ),
              ],
            ),
            if (planHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(planHint, style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w600)),
              ),
            if (lastHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 15, color: Colors.teal),
                    const SizedBox(width: 4),
                    Expanded(child: Text(lastHint, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            for (var si = 0; si < b.sets.length; si++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (!isCardio) ...[
                      InkWell(
                        onTap: () => setState(() => b.sets[si].warmup = !b.sets[si].warmup),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: b.sets[si].warmup
                                ? Colors.orange.withValues(alpha: 0.2)
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            b.sets[si].warmup ? l.sessionWarmupTag : '${si + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: b.sets[si].warmup ? Colors.orange : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: TextField(
                        controller: b.sets[si].weight,
                        keyboardType: numKb,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: isCardio ? l.sessionCardioDuration : l.sessionStrengthWeight,
                          suffixText: isCardio ? l.sessionCardioMins : 'kg',
                          prefixIcon: Icon(
                            isCardio ? Icons.timer_rounded : Icons.fitness_center_rounded,
                            size: 17,
                            color: isCardio ? const Color(0xFFEC407A) : const Color(0xFFEF5350),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: b.sets[si].reps,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: isCardio ? l.sessionCardioSteps : l.sessionStrengthReps,
                          suffixText: isCardio ? l.sessionCardioStepsUnit : l.sessionStrengthRepsUnit,
                          prefixIcon: Icon(
                            isCardio ? Icons.directions_walk_rounded : Icons.repeat_rounded,
                            size: 17,
                            color: const Color(0xFF42A5F5),
                          ),
                        ),
                      ),
                    ),
                    if (!isCardio)
                      IconButton(
                        tooltip: l.sessionCompleteSetTooltip,
                        icon: Icon(
                          b.sets[si].done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                          color: b.sets[si].done ? Colors.green : null,
                        ),
                        onPressed: () {
                          setState(() {
                            b.sets[si].done = !b.sets[si].done;
                            if (b.sets[si].done) {
                              b.sets[si].completedAtMs = DateTime.now().millisecondsSinceEpoch;
                              _startRestTimer(
                                exerciseName: L10nHelper.exerciseDisplayName(context, b.exercise.name),
                              );
                            }
                          });
                        },
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 19),
                      onPressed: () => setState(() => b.sets.removeAt(si)),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addSet(b),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text(isCardio ? l.sessionAddCardioRow : l.sessionAddStrengthRow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
