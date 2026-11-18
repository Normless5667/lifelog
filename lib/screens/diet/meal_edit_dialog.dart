import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../widgets/common.dart';

/// 手动添加 / 编辑一条饮食记录（全语义图标化）
class MealEditDialog extends StatefulWidget {
  final String date;
  final Meal? existing;
  final int initialMealType;

  const MealEditDialog({
    super.key,
    required this.date,
    this.existing,
    required this.initialMealType,
  });

  @override
  State<MealEditDialog> createState() => _MealEditDialogState();
}

class _MealEditDialogState extends State<MealEditDialog> {
  late int _mealType;
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _kcal;
  late final TextEditingController _p;
  late final TextEditingController _c;
  late final TextEditingController _f;

  static const _mealIcons = <IconData>[
    Icons.wb_twilight_rounded,
    Icons.wb_sunny_rounded,
    Icons.nights_stay_rounded,
    Icons.icecream_rounded,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _mealType = e?.mealType ?? widget.initialMealType;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(text: e?.amount ?? '');
    _kcal = TextEditingController(text: e == null ? '' : e.calories.round().toString());
    _p = TextEditingController(text: e == null ? '' : e.protein.round().toString());
    _c = TextEditingController(text: e == null ? '' : e.carbs.round().toString());
    _f = TextEditingController(text: e == null ? '' : e.fat.round().toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _kcal.dispose();
    _p.dispose();
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA726).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFFA726), size: 22),
          ),
          const SizedBox(width: 10),
          Text(widget.existing == null ? l.mealEditAddTitle : l.mealEditUpdateTitle),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _mealType,
              decoration: InputDecoration(
                labelText: l.mealEditTypeLabel,
                prefixIcon: Icon(_mealIcons[_mealType], color: const Color(0xFFFFA726)),
              ),
              items: [
                for (var i = 0; i < 4; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Row(
                      children: [
                        Icon(_mealIcons[i], size: 18),
                        const SizedBox(width: 8),
                        Text(L10nHelper.mealTypeLabel(context, i)),
                      ],
                    ),
                  )
              ],
              onChanged: (v) => setState(() => _mealType = v ?? _mealType),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: l.mealEditNameLabel,
                prefixIcon: const Icon(Icons.restaurant_rounded, color: Color(0xFF26A69A)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: l.mealEditAmountLabel,
                prefixIcon: const Icon(Icons.scale_rounded, color: Color(0xFF42A5F5)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kcal,
              keyboardType: numKb,
              decoration: InputDecoration(
                labelText: l.mealEditKcalLabel,
                suffixText: 'kcal',
                prefixIcon: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFEF5350)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _p,
                    keyboardType: numKb,
                    decoration: InputDecoration(
                      labelText: l.foodConfirmProtein,
                      prefixIcon: const Icon(Icons.egg_alt_rounded, size: 18, color: Color(0xFFEF5350)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _c,
                    keyboardType: numKb,
                    decoration: InputDecoration(
                      labelText: l.foodConfirmCarbs,
                      prefixIcon: const Icon(Icons.rice_bowl_rounded, size: 18, color: Color(0xFFFFA726)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _f,
                    keyboardType: numKb,
                    decoration: InputDecoration(
                      labelText: l.foodConfirmFat,
                      prefixIcon: const Icon(Icons.water_drop_rounded, size: 18, color: Color(0xFF42A5F5)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton.icon(
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              toast(context, l.mealEditNameRequired);
              return;
            }
            Navigator.pop(
              context,
              Meal(
                id: widget.existing?.id,
                date: widget.date,
                mealType: _mealType,
                name: _name.text.trim(),
                amount: _amount.text.trim(),
                calories: double.tryParse(_kcal.text) ?? 0,
                protein: double.tryParse(_p.text) ?? 0,
                carbs: double.tryParse(_c.text) ?? 0,
                fat: double.tryParse(_f.text) ?? 0,
                photoPath: widget.existing?.photoPath,
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
