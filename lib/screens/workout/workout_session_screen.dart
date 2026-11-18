import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../services/reminder_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'exercise_library_screen.dart';

/// 单次训练会话：开始 → 实时计时 (mm:ss) → 每组完成自动触发组间休息倒计时 → 结束保存总时长/总容量/总消耗
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
  final String lastHint;
  final String? planHint;

  _ExerciseBlock(this.exercise, this.sets, this.lastHint, {this.planHint});
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  Workout? _workout;
  final List<_ExerciseBlock> _blocks = [];
  bool _loading = true;
  double _userWeightKg = 65;

  // 会话实时正计时 + 组间休息倒计时
  Timer? _ticker;
  int _elapsedSeconds = 0;
  int _restTargetSeconds = 90;
  int _restRemaining = 0;
  bool _restPaused = false;

  @override
  void initState() {
    super.initState();
    ReminderService.setKeepScreenOn(true);
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    ReminderService.cancelRestAlarm();
    ReminderService.setKeepScreenOn(false);
    for (final b in _blocks) {
      for (final s in b.sets) {
        s.dispose();
      }
    }
    super.dispose();
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
      final ex = exMap[entry.key] ?? Exercise(id: entry.key, name: '动作', category: '其他');
      final last = await _formatLast(ex);
      _blocks.add(_ExerciseBlock(
        ex,
        entry.value.map((s) => _SetRow(w: s.weight, r: s.reps, warmup: s.isWarmup, done: true)).toList(),
        last,
      ));
    }

    // 如果是按 AI 训练计划一键开练，自动初始化动作与组数
    if (_blocks.isEmpty && widget.initialPlanExercises != null) {
      for (final pe in widget.initialPlanExercises!) {
        final ex = await Repo.findOrCreateExercise(pe.name);
        final lastSets = await Repo.lastSetsForExercise(ex.id!, excludeWorkoutId: widget.workoutId);
        final lastWork = lastSets.where((s) => !s.isWarmup).toList();
        final hintWeight = double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(pe.weightHint)?.group(0) ?? '');
        final hintReps = int.tryParse(RegExp(r'\d+').firstMatch(pe.reps)?.group(0) ?? '') ?? 10;
        final defW = hintWeight ?? (lastWork.isEmpty ? 0.0 : lastWork.first.weight);
        final defR = lastWork.isEmpty ? hintReps : lastWork.first.reps;
        final lastStr = await _formatLast(ex);
        final rows = [for (var i = 0; i < pe.sets.clamp(1, 10); i++) _SetRow(w: defW, r: defR)];
        _blocks.add(_ExerciseBlock(
          ex,
          rows,
          lastStr,
          planHint: '计划目标：${pe.sets}组 × ${pe.reps}${pe.weightHint.isNotEmpty ? '（建议 ${pe.weightHint}）' : ''}',
        ));
      }
    }

    if (w != null) {
      if (w.endTime != null && !widget.isNew) {
        _elapsedSeconds = ((w.endTime! - w.startTime) ~/ 1000).clamp(0, 86400);
      } else {
        _elapsedSeconds = ((DateTime.now().millisecondsSinceEpoch - w.startTime) ~/ 1000).clamp(0, 86400);
      }
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
        if (_restRemaining > 0 && !_restPaused) {
          _restRemaining--;
          if (_restRemaining == 0) {
            ReminderService.vibrateShort();
            toast(context, '⏱️ 组间休息结束！开始下一组吧 💪');
          }
        }
      });
    });

    if (!mounted) return;
    setState(() {
      _workout = w;
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
    setState(() {
      _restRemaining = dur;
      _restPaused = false;
    });
    ReminderService.scheduleRestAlarm(
      dur,
      nextHint: exerciseName != null ? '「$exerciseName」休息结束，准备下一组 💪' : null,
    );
  }

  void _stopRestTimer() {
    setState(() {
      _restRemaining = 0;
      _restPaused = false;
    });
    ReminderService.cancelRestAlarm();
  }

  Future<String> _formatLast(Exercise ex) async {
    final last = await Repo.lastSetsForExercise(ex.id!, excludeWorkoutId: widget.workoutId);
    final work = last.where((s) => !s.isWarmup).toList();
    if (work.isEmpty) return '';
    if (ex.category == '有氧') {
      return '上次：${work.map((s) => '${fmtNum(s.weight)}分钟${s.reps > 0 ? ' · ${s.reps}步' : ''}').join('  ')}';
    }
    return '上次：${work.map((s) => '${fmtNum(s.weight, digits: 1)}kg×${s.reps}').join('  ')}';
  }

  Future<void> _addExercise() async {
    final ex = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen(selectMode: true)),
    );
    if (ex == null) return;
    final lastSets = await Repo.lastSetsForExercise(ex.id!, excludeWorkoutId: widget.workoutId);
    final lastWork = lastSets.where((s) => !s.isWarmup).toList();
    final isCardio = ex.category == '有氧';
    final defW = lastWork.isEmpty ? (isCardio ? 30.0 : 0.0) : lastWork.first.weight;
    final defR = lastWork.isEmpty ? 0 : lastWork.first.reps;
    final hint = await _formatLast(ex);
    if (!mounted) return;
    setState(() {
      _blocks.add(_ExerciseBlock(ex, [_SetRow(w: defW, r: defR)], hint));
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
      if (b.exercise.category == '有氧') continue;
      for (final s in b.sets) {
        final w = double.tryParse(s.weight.text) ?? 0;
        final r = int.tryParse(s.reps.text) ?? 0;
        if (!s.warmup && (w > 0 || r > 0)) {
          workSets++;
          vol += w * r;
        }
      }
    }
    final mins = (_elapsedSeconds / 60.0).clamp(1.0, 180.0);
    final kcal = Nutrition.calcMetCalories(met: Nutrition.strengthMet, weightKg: _userWeightKg, minutes: mins);
    return (sets: workSets, volume: vol, kcal: kcal);
  }

  Future<void> _finish() async {
    final w = _workout;
    if (w == null) return;
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
    w.endTime = w.startTime + (_elapsedSeconds * 1000);
    await Repo.updateWorkout(w);
    await Repo.replaceSets(w.id!, allSets);
    if (!mounted) return;
    final stats = _liveStats();
    toast(
      context,
      '训练完成！耗时 ${_elapsedSeconds ~/ 60} 分钟 · ${stats.sets} 组 · 容量 ${fmtNum(stats.volume)} kg · 消耗约 ${fmtNum(stats.kcal)} kcal',
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      _fmtClock(_elapsedSeconds),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFFEF5350),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${stats.sets}组 · ${fmtNum(stats.volume)}kg',
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
              label: const Text('结束训练'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addExercise,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加动作'),
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
                              text: '训练计时已开始！\n点击下方按钮选择动作，每完成一组点右侧 ✓ 自动开启组间休息倒计时',
                              actionLabel: '选择训练动作',
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

  /// 顶部组间休息计时器横幅（可设 60 / 90 / 120 / 180 秒，支持暂停 / +15s / 跳过）
  Widget _restTimerBanner() {
    final cs = Theme.of(context).colorScheme;
    final active = _restRemaining > 0;
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
                '组间休息倒计时：${_fmtClock(_restRemaining)}${_restPaused ? ' (已暂停)' : ''}',
                style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _restPaused ? '继续' : '暂停',
              icon: Icon(_restPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              onPressed: () {
                setState(() => _restPaused = !_restPaused);
                if (_restPaused) {
                  ReminderService.cancelRestAlarm();
                } else {
                  ReminderService.scheduleRestAlarm(_restRemaining);
                }
              },
            ),
            TextButton(
              onPressed: () => _startRestTimer(seconds: _restRemaining + 15),
              child: const Text('+15s'),
            ),
            TextButton(
              onPressed: _stopRestTimer,
              child: const Text('跳过'),
            ),
          ] else ...[
            const Text('组间休息时长：', style: TextStyle(fontSize: 12)),
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
              tooltip: '立即开始休息计时',
              icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.teal),
              onPressed: () => _startRestTimer(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExerciseCard(int bi, TextInputType numKb) {
    final b = _blocks[bi];
    final isCardio = b.exercise.category == '有氧';
    final vis = categoryVisual(b.exercise.category);
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
                    b.exercise.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: vis.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(b.exercise.category, style: TextStyle(fontSize: 11, color: vis.color, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => setState(() => _blocks.removeAt(bi)),
                ),
              ],
            ),
            if (b.planHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(b.planHint!, style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w600)),
              ),
            if (b.lastHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 15, color: Colors.teal),
                    const SizedBox(width: 4),
                    Expanded(child: Text(b.lastHint, style: Theme.of(context).textTheme.bodySmall)),
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
                            b.sets[si].warmup ? '热' : '${si + 1}',
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
                        decoration: InputDecoration(
                          labelText: isCardio ? '时长' : '重量',
                          suffixText: isCardio ? '分' : 'kg',
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
                        decoration: InputDecoration(
                          labelText: isCardio ? '步数' : '次数',
                          suffixText: isCardio ? '步' : '次',
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
                        tooltip: '完成本组并开始休息倒计时',
                        icon: Icon(
                          b.sets[si].done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                          color: b.sets[si].done ? Colors.green : null,
                        ),
                        onPressed: () {
                          setState(() {
                            b.sets[si].done = !b.sets[si].done;
                            if (b.sets[si].done) {
                              b.sets[si].completedAtMs = DateTime.now().millisecondsSinceEpoch;
                              _startRestTimer(exerciseName: b.exercise.name);
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
                label: Text(isCardio ? '再加一段有氧记录' : '加一组（点 ✓ 完成本组并自动倒计时休息）'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
