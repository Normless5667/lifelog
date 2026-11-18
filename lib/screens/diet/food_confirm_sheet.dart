import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../models/models.dart';

/// AI 识别出食物后，用户在此核对、修改数值，再保存到数据库
class FoodConfirmSheet extends StatefulWidget {
  final String date;
  final int initialMealType;
  final List<FoodEstimate> estimates;
  final String aiNote;
  final String? photoPath;

  const FoodConfirmSheet({
    super.key,
    required this.date,
    required this.initialMealType,
    required this.estimates,
    required this.aiNote,
    this.photoPath,
  });

  @override
  State<FoodConfirmSheet> createState() => _FoodConfirmSheetState();
}

class _RowCtrls {
  final TextEditingController name;
  final TextEditingController amount;
  final TextEditingController kcal;
  final TextEditingController p;
  final TextEditingController c;
  final TextEditingController f;
  bool checked = true;

  _RowCtrls(FoodEstimate e)
      : name = TextEditingController(text: e.name),
        amount = TextEditingController(text: e.amount),
        kcal = TextEditingController(text: e.calories.round().toString()),
        p = TextEditingController(text: e.protein.round().toString()),
        c = TextEditingController(text: e.carbs.round().toString()),
        f = TextEditingController(text: e.fat.round().toString());

  void dispose() {
    name.dispose();
    amount.dispose();
    kcal.dispose();
    p.dispose();
    c.dispose();
    f.dispose();
  }
}

class _FoodConfirmSheetState extends State<FoodConfirmSheet> {
  late int _mealType;
  late final List<_RowCtrls> _rows;

  @override
  void initState() {
    super.initState();
    _mealType = widget.initialMealType;
    _rows = widget.estimates.map(_RowCtrls.new).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    for (final r in _rows) {
      if (!r.checked || r.name.text.trim().isEmpty) continue;
      await Repo.saveMeal(Meal(
        date: widget.date,
        mealType: _mealType,
        name: r.name.text.trim(),
        amount: r.amount.text.trim(),
        calories: double.tryParse(r.kcal.text) ?? 0,
        protein: double.tryParse(r.p.text) ?? 0,
        carbs: double.tryParse(r.c.text) ?? 0,
        fat: double.tryParse(r.f.text) ?? 0,
        photoPath: widget.photoPath,
      ));
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('AI 估算结果（可修改）', style: Theme.of(context).textTheme.titleLarge),
            if (widget.aiNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(widget.aiNote, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: [for (var i = 0; i < 4; i++) ButtonSegment(value: i, label: Text(mealTypeNames[i]))],
              selected: {_mealType},
              onSelectionChanged: (s) => setState(() => _mealType = s.first),
            ),
            const SizedBox(height: 12),
            for (final r in _rows)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: r.checked,
                            onChanged: (v) => setState(() => r.checked = v ?? true),
                          ),
                          Expanded(
                            flex: 3,
                            child: TextField(controller: r.name, decoration: const InputDecoration(labelText: '食物')),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(controller: r.amount, decoration: const InputDecoration(labelText: '份量')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: r.kcal, keyboardType: numKb, decoration: const InputDecoration(labelText: '热量 kcal'))),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: r.p, keyboardType: numKb, decoration: const InputDecoration(labelText: '蛋白 g'))),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: r.c, keyboardType: numKb, decoration: const InputDecoration(labelText: '碳水 g'))),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: r.f, keyboardType: numKb, decoration: const InputDecoration(labelText: '脂肪 g'))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('添加到今日饮食'),
            ),
          ],
        ),
      ),
    );
  }
}
