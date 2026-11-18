import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/repo.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// 动作库：既可以作为独立管理页面，也可以传入 [selectMode] 供训练会话选动作（带部位彩色图标）
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
    final name = TextEditingController();
    var cat = _cat;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center_rounded, color: Color(0xFFEF5350), size: 20),
              ),
              const SizedBox(width: 10),
              const Text('添加自定义动作'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: cat,
                decoration: const InputDecoration(
                  labelText: '部位分类',
                  prefixIcon: Icon(Icons.category_rounded, color: Color(0xFF42A5F5)),
                ),
                items: AppDatabase.exerciseCategories.map((c) {
                  final vis = categoryVisual(c);
                  return DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Icon(vis.icon, size: 18, color: vis.color),
                        const SizedBox(width: 8),
                        Text(c),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setD(() => cat = v ?? cat),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '动作名称',
                  prefixIcon: Icon(Icons.edit_rounded, color: Color(0xFF26A69A)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加'),
            ),
          ],
        ),
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
    final filtered = _all.where((e) => e.category == _cat).toList();
    final vis = categoryVisual(_cat);
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
            Text(widget.selectMode ? '选择训练动作' : '动作库'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustom,
        icon: const Icon(Icons.add_rounded),
        label: const Text('自定义动作'),
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
                    label: Text(c),
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
                    title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(e.isCustom ? '$_cat · 自定义动作' : '$_cat肌群训练'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (e.isCustom)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              if (await confirm(context, '删除自定义动作「${e.name}」？')) {
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
