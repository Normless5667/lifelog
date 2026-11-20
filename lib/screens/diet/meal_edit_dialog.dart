import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/nutrition.dart';
import '../../widgets/common.dart';

/// 手动添加 / 快速记录 / 编辑一条饮食记录（支持近7天常吃一键填入与极简模式）
class MealEditDialog extends StatefulWidget {
  final String date;
  final Meal? existing;
  final int initialMealType;
  final List<Meal> recentMeals;

  const MealEditDialog({
    super.key,
    required this.date,
    this.existing,
    required this.initialMealType,
    this.recentMeals = const [],
  });

  @override
  State<MealEditDialog> createState() => _MealEditDialogState();
}

class _MealEditDialogState extends State<MealEditDialog> {
  late int _mealType;
  late bool _showDetails;
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
    _showDetails = e != null;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(text: e?.amount ?? '');
    _kcal = TextEditingController(text: e == null ? '' : e.calories.round().toString());
    _p = TextEditingController(text: e == null ? '' : e.protein.round().toString());
    _c = TextEditingController(text: e == null ? '' : e.carbs.round().toString());
    _f = TextEditingController(text: e == null ? '' : e.fat.round().toString());
  }

  void _applyRecentMeal(Meal m) {
    setState(() {
      _name.text = m.name;
      _amount.text = m.amount ?? '';
      _kcal.text = m.calories > 0 ? m.calories.round().toString() : '';
      _p.text = m.protein > 0 ? m.protein.round().toString() : '';
      _c.text = m.carbs > 0 ? m.carbs.round().toString() : '';
      _f.text = m.fat > 0 ? m.fat.round().toString() : '';
    });
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
    final warning = AppColors.warning(context);
    final teal = AppColors.teal(context);
    final info = AppColors.info(context);
    final proteinColor = AppColors.macroProtein(context);
    final carbsColor = AppColors.macroCarbs(context);
    final fatColor = AppColors.macroFat(context);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, warning),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.restaurant_menu_rounded, color: warning, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              widget.existing == null ? l.mealEditAddTitle : l.mealEditUpdateTitle,
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
            if (widget.existing == null && widget.recentMeals.isNotEmpty) ...[
              Text(l.mealQuickRecentTitle, style: AppTypography.caption(context)),
              const SizedBox(height: AppSpacing.xs),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final rm in widget.recentMeals)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '${rm.name} · ${rm.calories.round()} kcal',
                            style: AppTypography.badge(context),
                          ),
                          onPressed: () => _applyRecentMeal(rm),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            DropdownButtonFormField<int>(
              initialValue: _mealType,
              decoration: InputDecoration(
                labelText: l.mealEditTypeLabel,
                prefixIcon: Icon(_mealIcons[_mealType], color: warning),
              ),
              items: [
                for (var i = 0; i < 4; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Row(
                      children: [
                        Icon(_mealIcons[i], size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text(L10nHelper.mealTypeLabel(context, i)),
                      ],
                    ),
                  )
              ],
              onChanged: (v) => setState(() => _mealType = v ?? _mealType),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.mealEditNameLabel,
                prefixIcon: Icon(Icons.restaurant_rounded, color: teal),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _kcal,
              keyboardType: numKb,
              decoration: InputDecoration(
                labelText: l.mealEditKcalLabel,
                suffixText: 'kcal',
                prefixIcon: Icon(Icons.local_fire_department_rounded, color: AppColors.danger(context)),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(
                  _showDetails ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _showDetails ? l.mealCollapseMacrosBtn : l.mealExpandMacrosBtn,
                  style: AppTypography.caption(context),
                ),
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _amount,
                decoration: InputDecoration(
                  labelText: l.mealEditAmountLabel,
                  prefixIcon: Icon(Icons.scale_rounded, color: info),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _p,
                      keyboardType: numKb,
                      decoration: InputDecoration(
                        labelText: l.foodConfirmProtein,
                        prefixIcon: Icon(Icons.egg_alt_rounded, size: 17, color: proteinColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _c,
                      keyboardType: numKb,
                      decoration: InputDecoration(
                        labelText: l.foodConfirmCarbs,
                        prefixIcon: Icon(Icons.rice_bowl_rounded, size: 17, color: carbsColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _f,
                      keyboardType: numKb,
                      decoration: InputDecoration(
                        labelText: l.foodConfirmFat,
                        prefixIcon: Icon(Icons.water_drop_rounded, size: 17, color: fatColor),
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
                calories: Nutrition.clampMealCalories(Nutrition.parsePlainDouble(_kcal.text) ?? 0),
                protein: Nutrition.clampMealMacro(Nutrition.parsePlainDouble(_p.text) ?? 0),
                carbs: Nutrition.clampMealMacro(Nutrition.parsePlainDouble(_c.text) ?? 0),
                fat: Nutrition.clampMealMacro(Nutrition.parsePlainDouble(_f.text) ?? 0),
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
