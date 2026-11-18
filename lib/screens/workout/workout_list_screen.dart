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

/// 训练板块：
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
      var workSets = 0;
      var vol = 0.0;
      for (final s in sets) {
        final ex = exMap[s.exerciseId];
        final n = ex?.name ?? '';
        primaryCat ??= ex?.category;
        if (n.isNotEmpty && !names.contains(n)) names.add(n);
        if (!s.isWarmup) {
          workSets++;
          vol += s.weight * s.reps;
        }
      }
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
      out.add(_WorkoutSummary(w, names, primaryCat ?? L10nHelper.cardioOtherCategory, workSets, vol, kcal));
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.fitness_center_rounded, color: Color(0xFFEF5350), size: 20),
            ),
            const SizedBox(width: 10),
            Text(l.workoutTitle),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()));
              _load();
            },
            icon: const Icon(Icons.grid_view_rounded),
            label: Text(l.workoutExerciseLibBtn),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tab == 0 ? () => _startNew() : () => _addOrEditCardio(),
        icon: Icon(_tab == 0 ? Icons.play_arrow_rounded : Icons.directions_run_rounded),
        label: Text(_tab == 0 ? l.workoutStartStrengthBtn : l.workoutLogCardioBtn),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.fitness_center_rounded),
                        label: Text(l.workoutTabStrength),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.directions_run_rounded),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      children: [
        if (_plan != null) _activePlanCard(_plan!),
        if (_items.isNotEmpty) _volumeBarCard(),
        SectionTitle(l.workoutHistoryTitle, icon: Icons.history_rounded, iconColor: const Color(0xFFEF5350)),
        if (_items.isEmpty)
          EmptyHint(
            icon: Icons.fitness_center_rounded,
            text: l.workoutEmptyStrengthHint,
            actionLabel: l.workoutEmptyStrengthBtn,
            onAction: () => _startNew(),
          )
        else
          for (final it in _items) _workoutItemCard(it),
      ],
    );
  }

  Widget _activePlanCard(TrainingPlan plan) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_rounded, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.workoutActivePlanTitle(plan.planName),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Text(l.workoutTapSplitHint, style: const TextStyle(fontSize: 11, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: plan.days.map((d) {
                return ActionChip(
                  avatar: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Colors.teal),
                  label: Text(l.workoutPlanSplitChip(d.day, d.focus, d.exercises.length)),
                  onPressed: () => _startNew(
                    planExercises: d.exercises,
                    note: '${plan.planName} - ${d.day}(${d.focus})',
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardioTab() {
    final l = context.l10n;
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: _cardios.length,
      itemBuilder: (_, i) {
        final c = _cardios[i];
        final typeLabel = L10nHelper.cardioTypeLabel(context, c.type);
        return Card(
          child: ListTile(
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFEC407A).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.directions_run_rounded, color: Color(0xFFEC407A)),
            ),
            title: Text(
              '${l.workoutCardioItemTitle(typeLabel, fmtNum(c.durationMinutes))}${c.distanceKm != null ? ' · ${fmtNum(c.distanceKm!, digits: 2)} km' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${L10nHelper.friendlyDateL10n(context, c.date)} · MET ${Nutrition.cardioMets[c.type] ?? 5.0}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC407A).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '-${fmtNum(c.calories)} kcal',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEC407A), fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    if (await confirm(context, l.workoutDeleteCardioConfirm)) {
                      await Repo.deleteCardioRecord(c.id!);
                      _load();
                    }
                  },
                ),
              ],
            ),
            onTap: () => _addOrEditCardio(c),
          ),
        );
      },
    );
  }

  /// 最近 7 次训练容量柱状可视化卡片
  Widget _volumeBarCard() {
    final l = context.l10n;
    final recent = _items.take(7).toList().reversed.toList();
    final maxVol = recent.fold<double>(1, (m, e) => e.volume > m ? e.volume : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart_rounded, color: Color(0xFFEF5350), size: 20),
                const SizedBox(width: 6),
                Text(l.workoutVolumeChartTitle, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: recent.map((it) {
                  final ratio = (it.volume / maxVol).clamp(0.08, 1.0);
                  final vis = categoryVisual(it.primaryCategory);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(fmtNum(it.volume), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Container(
                            height: 64 * ratio,
                            decoration: BoxDecoration(
                              color: vis.color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(it.workout.date.substring(5), style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workoutItemCard(_WorkoutSummary it) {
    final l = context.l10n;
    final w = it.workout;
    final durMin = w.endTime == null ? null : ((w.endTime! - w.startTime) ~/ 60000);
    final vis = categoryVisual(it.primaryCategory);
    final displayNames = it.exerciseNames.map((n) => L10nHelper.exerciseDisplayName(context, n)).toList();
    return Card(
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: vis.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(vis.icon, color: vis.color, size: 24),
        ),
        title: Text(
          displayNames.isEmpty ? l.workoutEmptySessionTitle : displayNames.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text([
            L10nHelper.friendlyDateL10n(context, w.date),
            if (durMin != null && durMin > 0) l.workoutSessionDuration(durMin),
            l.workoutSessionSets(it.workSets),
            if (it.volume > 0) l.workoutSessionVolume(fmtNum(it.volume)),
            if (it.estCalories > 0) l.workoutSessionBurn(fmtNum(it.estCalories)),
          ].join(' · ')),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirm(context, l.workoutDeleteSessionConfirm)) {
                  await Repo.deleteWorkout(w.id!);
                  _load();
                }
              },
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () => _openSession(w.id!),
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
    _dist = TextEditingController(text: e?.distanceKm != null ? fmtNum(e!.distanceKm!, digits: 2) : '');
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
    final m = double.tryParse(_mins.text) ?? 0;
    final met = Nutrition.cardioMets[_type] ?? 5.0;
    final c = Nutrition.calcMetCalories(met: met, weightKg: widget.weightKg, minutes: m);
    _kcal.text = fmtNum(c);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const numKb = TextInputType.numberWithOptions(decimal: true);
    final met = Nutrition.cardioMets[_type] ?? 5.0;
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEC407A).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_run_rounded, color: Color(0xFFEC407A), size: 22),
          ),
          const SizedBox(width: 10),
          Text(widget.existing == null ? l.cardioDialogAddTitle : l.cardioDialogEditTitle),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, color: Colors.teal),
              title: Text(L10nHelper.friendlyDateL10n(context, _date), style: const TextStyle(fontWeight: FontWeight.bold)),
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
              decoration: InputDecoration(
                labelText: l.cardioTypeLabel,
                prefixIcon: const Icon(Icons.directions_run_rounded, color: Color(0xFFEC407A)),
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
            const SizedBox(height: 12),
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
                      prefixIcon: const Icon(Icons.timer_rounded, color: Color(0xFFFFA726)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _dist,
                    keyboardType: numKb,
                    decoration: InputDecoration(
                      labelText: l.cardioDistanceLabel,
                      suffixText: 'km',
                      prefixIcon: const Icon(Icons.place_rounded, color: Color(0xFF42A5F5)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kcal,
              keyboardType: numKb,
              onChanged: (_) => _manualKcal = true,
              decoration: InputDecoration(
                labelText: l.cardioEstBurnLabel(fmtNum(widget.weightKg, digits: 1), '$met'),
                suffixText: 'kcal',
                prefixIcon: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFEF5350)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton.icon(
          onPressed: () {
            final mins = double.tryParse(_mins.text) ?? 0;
            if (mins <= 0) {
              toast(context, l.cardioDurationRequired);
              return;
            }
            Navigator.pop(
              context,
              CardioRecord(
                id: widget.existing?.id,
                date: _date,
                type: _type,
                durationMinutes: mins,
                distanceKm: double.tryParse(_dist.text),
                calories: double.tryParse(_kcal.text) ?? 0,
                createdAt: widget.existing?.createdAt,
              ),
            );
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(l.commonSave),
        ),
      ],
    );
  }
}
