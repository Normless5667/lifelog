import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/repo.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// 动作库：既可以作为独立管理页面，也可以传入 [selectMode] 供训练会话选动作
class ExerciseLibraryScreen extends StatefulWidget {
  final bool selectMode;
  const ExerciseLibraryScreen({super.key, this.selectMode = false});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  List<Exercise> _all = [];
  String _cat = AppDatabase.exerciseCategories.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Repo.getExercises();
    if (!mounted) return;
    setState(() => _all = list);
  }

  Future<void> _addCustom() async {
    final l = context.l10n;
    final name = TextEditingController();
    var cat = _cat;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final workoutColor = AppColors.moduleWorkout(ctx);
          final info = AppColors.info(ctx);
          final teal = AppColors.teal(ctx);
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(ctx, workoutColor),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(Icons.fitness_center_rounded, color: workoutColor, size: 19),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(l.exerciseCustomDialogTitle, style: AppTypography.sectionTitle(ctx))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: cat,
                  decoration: InputDecoration(
                    labelText: l.exerciseCategoryLabel,
                    prefixIcon: Icon(Icons.category_rounded, color: info),
                  ),
                  items: AppDatabase.exerciseCategories.map((c) {
                    final vis = categoryVisual(c);
                    return DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Icon(vis.icon, size: 18, color: AppColors.adaptForDark(ctx, vis.color)),
                          const SizedBox(width: AppSpacing.sm),
                          Text(L10nHelper.exerciseCategoryLabel(ctx, c)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setD(() => cat = v ?? cat),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.exerciseNameLabel,
                    prefixIcon: Icon(Icons.edit_rounded, color: teal),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.commonAdd),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final ex = Exercise(name: name.text.trim(), category: cat, isCustom: true);
      ex.id = await Repo.addExercise(ex);
      await _load();
      if (widget.selectMode && mounted) Navigator.pop(context, ex);
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final filtered = _all.where((e) => e.category == _cat).toList();
    final vis = categoryVisual(_cat);
    final catLabel = L10nHelper.exerciseCategoryLabel(context, _cat);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: vis.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(vis.icon, color: vis.color, size: 20),
            ),
            const SizedBox(width: 10),
            Text(widget.selectMode ? l.exerciseSelectTitle : l.exerciseLibTitle),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustom,
        icon: const Icon(Icons.add_rounded),
        label: Text(l.exerciseAddCustomBtn),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: AppDatabase.exerciseCategories.map((c) {
                final cv = categoryVisual(c);
                final selected = _cat == c;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(cv.icon, size: 16, color: selected ? cv.color : null),
                    label: Text(L10nHelper.exerciseCategoryLabel(context, c)),
                    selected: selected,
                    onSelected: (_) => setState(() => _cat = c),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final e = filtered[i];
                final displayName = L10nHelper.exerciseDisplayName(context, e.name);
                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: vis.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(vis.icon, color: vis.color, size: 22),
                    ),
                    title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      e.isCustom
                          ? l.exerciseCustomSubtitle(catLabel)
                          : l.exercisePresetSubtitle(catLabel),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (e.isCustom)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              if (await confirm(context, l.exerciseDeleteConfirm(displayName))) {
                                await Repo.deleteExercise(e.id!);
                                _load();
                              }
                            },
                          ),
                        if (widget.selectMode) const Icon(Icons.add_circle_outline_rounded, color: Colors.teal),
                      ],
                    ),
                    onTap: widget.selectMode ? () => Navigator.pop(context, e) : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
