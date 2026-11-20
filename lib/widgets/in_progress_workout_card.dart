import 'dart:async';

import 'package:flutter/material.dart';

import '../db/repo.dart';
import '../models/models.dart';
import '../services/nutrition.dart';
import '../services/usage_telemetry_service.dart';
import '../utils/date_utils.dart';
import 'common.dart';

/// 进行中训练会话摘要快照（来自 workouts 表 end_time IS NULL 的记录）
class InProgressWorkoutSnapshot {
  final Workout workout;
  final List<String> exerciseNames;
  final int workSets;
  final double volume;
  final double estCalories;

  const InProgressWorkoutSnapshot({
    required this.workout,
    required this.exerciseNames,
    required this.workSets,
    required this.volume,
    required this.estCalories,
  });

  int elapsedSecondsAt(int nowMs) =>
      ((nowMs - workout.startTime) ~/ 1000).clamp(0, 86400);

  int elapsedHoursAt(int nowMs) =>
      ((nowMs - workout.startTime) ~/ 3600000).clamp(0, 999);

  bool isStaleAt(int nowMs) => (nowMs - workout.startTime) >= 6 * 3600 * 1000;
}

class InProgressWorkoutHelper {
  InProgressWorkoutHelper._();

  static int? _promptedStaleWorkoutId;

  static Future<InProgressWorkoutSnapshot?> loadSnapshot({
    required double weightKg,
  }) async {
    final w = await Repo.getInProgressWorkout();
    if (w == null || w.id == null) return null;
    final sets = await Repo.getSets(w.id!);
    final exercises = await Repo.getExercises();
    final exMap = {for (final e in exercises) e.id: e};
    final names = <String>[];
    final strengthRows = <({double weight, int reps, bool isWarmup})>[];
    for (final s in sets) {
      final ex = exMap[s.exerciseId];
      final n = ex?.name ?? '';
      if (n.isNotEmpty && !names.contains(n)) names.add(n);
      if (ex != null && L10nHelper.isCardioCategory(ex.category)) continue;
      strengthRows.add((weight: s.weight, reps: s.reps, isWarmup: s.isWarmup));
    }
    final st = Nutrition.calcStrengthStats(strengthRows);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedMins = ((nowMs - w.startTime) / 60000.0).clamp(0.0, 180.0);
    final estKcal = Nutrition.burnForWorkout(
      workout: w,
      totalVolumeKg: st.volume,
      workSets: st.sets,
      weightKg: weightKg,
      overrideElapsedMinutes: elapsedMins,
    );
    return InProgressWorkoutSnapshot(
      workout: w,
      exerciseNames: names,
      workSets: st.sets,
      volume: st.volume,
      estCalories: estKcal,
    );
  }

  /// 直接结束并保存进行中的训练会话
  static Future<void> finishAndSave(
    BuildContext context,
    InProgressWorkoutSnapshot snap, {
    required double weightKg,
  }) async {
    final w = snap.workout;
    if (w.id == null) return;
    final sets = await Repo.getSets(w.id!);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedSecs = snap.elapsedSecondsAt(nowMs);
    if (sets.isEmpty) {
      UsageTelemetryService.instance.trackFeature(
        'start_workout',
        'cancel',
        durationMs: elapsedSecs * 1000,
      );
      await Repo.deleteWorkout(w.id!);
      return;
    }
    w.date = dateOnlyStr(w.date);
    w.endTime = w.startTime + (elapsedSecs * 1000);
    await Repo.updateWorkout(w);
    UsageTelemetryService.instance.trackFeature(
      'start_workout',
      'success',
      durationMs: elapsedSecs * 1000,
    );
    final burn = Nutrition.burnForWorkout(
      workout: w,
      totalVolumeKg: snap.volume,
      workSets: snap.workSets,
      weightKg: weightKg,
    );
    if (!context.mounted) return;
    toast(
      context,
      context.l10n.sessionFinishedToast(
        elapsedSecs ~/ 60,
        snap.workSets,
        fmtNum(snap.volume),
        fmtNum(burn),
      ),
    );
  }

  /// 冷启动检测到超过 6 小时未结束的训练时，提示用户选择继续 / 结束并保存 / 放弃
  static Future<void> maybePromptStale(
    BuildContext context,
    InProgressWorkoutSnapshot snap, {
    required double weightKg,
    required VoidCallback onResume,
    required VoidCallback onChanged,
  }) async {
    final wid = snap.workout.id;
    if (wid == null || _promptedStaleWorkoutId == wid) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!snap.isStaleAt(nowMs)) return;
    _promptedStaleWorkoutId = wid;
    if (!context.mounted) return;

    final l = context.l10n;
    final hours = snap.elapsedHoursAt(nowMs);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.workoutStaleTitle, style: AppTypography.sectionTitle(ctx)),
        content: Text(
          l.workoutStaleDesc(hours, snap.workSets),
          style: AppTypography.body(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(l.workoutDiscardBtn),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'finish'),
            child: Text(l.workoutFinishSaveBtn),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'resume'),
            child: Text(l.workoutResumeBtn),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'resume') {
      onResume();
    } else if (choice == 'finish') {
      await finishAndSave(context, snap, weightKg: weightKg);
      onChanged();
    } else if (choice == 'discard') {
      await Repo.deleteWorkout(wid);
      onChanged();
    }
  }
}

/// 训练列表页与首页共用的「🔴 训练进行中」恢复卡片（本地 ValueNotifier 局部走表，不重绘整页）
class InProgressWorkoutCard extends StatefulWidget {
  final InProgressWorkoutSnapshot snapshot;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  const InProgressWorkoutCard({
    super.key,
    required this.snapshot,
    required this.onResume,
    required this.onFinish,
  });

  @override
  State<InProgressWorkoutCard> createState() => _InProgressWorkoutCardState();
}

class _InProgressWorkoutCardState extends State<InProgressWorkoutCard>
    with WidgetsBindingObserver {
  late final ValueNotifier<int> _elapsedNotifier;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _elapsedNotifier = ValueNotifier<int>(_computeElapsed());
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant InProgressWorkoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _elapsedNotifier.value = _computeElapsed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _elapsedNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopTimer();
    } else if (state == AppLifecycleState.resumed) {
      _elapsedNotifier.value = _computeElapsed();
      _startTimer();
    }
  }

  int _computeElapsed() =>
      widget.snapshot.elapsedSecondsAt(DateTime.now().millisecondsSinceEpoch);

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _elapsedNotifier.value = _computeElapsed();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _fmtClock(int secs) {
    final h = secs ~/ 3600;
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final danger = AppColors.danger(context);
    final workoutColor = AppColors.moduleWorkout(context);
    final s = widget.snapshot;
    final displayNames =
        s.exerciseNames.map((n) => L10nHelper.exerciseDisplayName(context, n)).toList();
    final summaryParts = <String>[
      if (displayNames.isNotEmpty)
        displayNames.take(2).join(' · ')
      else if (s.workout.note != null && s.workout.note!.trim().isNotEmpty)
        s.workout.note!.trim(),
      if (s.workSets > 0) l.workoutCompactSets(s.workSets),
      if (s.volume > 0) '${fmtNum(s.volume)} kg',
    ];

    return SurfaceCard(
      backgroundColor: AppColors.softBg(context, danger, lightAlpha: 0.06, darkAlpha: 0.14),
      borderColor: AppColors.softBorder(context, danger, lightAlpha: 0.30, darkAlpha: 0.42),
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: danger, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l.workoutInProgressBadge,
                  style: AppTypography.cardTitle(context, color: danger),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: _elapsedNotifier,
                builder: (ctx, secs, _) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.softBg(ctx, workoutColor, lightAlpha: 0.12, darkAlpha: 0.22),
                    borderRadius: AppRadius.bPill,
                  ),
                  child: Text(
                    l.workoutInProgressElapsed(_fmtClock(secs)),
                    style: AppTypography.badge(ctx, color: workoutColor),
                  ),
                ),
              ),
            ],
          ),
          if (summaryParts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              summaryParts.join(' · '),
              style: AppTypography.bodySecondary(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onResume,
                  style: FilledButton.styleFrom(
                    backgroundColor: workoutColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(l.workoutResumeBtn),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onFinish,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                  label: Text(l.workoutFinishSaveBtn),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
