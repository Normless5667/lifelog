import 'package:flutter/material.dart';

import '../../debug/debug_server.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/nutrition.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';

/// 快速记饮食弹窗的完成路径，用于区分埋点统计（quick_log_diet / meal_reuse_recent / meal_edit_full）
enum QuickLogMealPath {
  /// Step 1 输入名称 → Step 2 自动带出历史或 AI 估算 → 确认保存
  quickSave,

  /// Step 1 直接点「最近吃过」列表项一键保存
  reuseRecent,

  /// 用户点击「完整表单」或历史匹配与 AI 估算均失败时回退到 6 格完整表单
  openFullForm,
}

class QuickLogMealResult {
  final QuickLogMealPath path;
  final Meal meal;
  final String? fallbackError;

  const QuickLogMealResult({
    required this.path,
    required this.meal,
    this.fallbackError,
  });
}

enum _QuickStep { input, estimating, confirm }

/// v3.5.0 两步式快速记饮食弹窗：
/// - 第一步只展示 1 个输入框「吃了什么」+「最近吃过」列表（点一下直接带出热量营养素并保存）
/// - 点击「下一步」：优先匹配历史同名记录 → 未命中则调用 AI 文字模型估算 → 均失败自动回退 6 格完整表单
class QuickLogMealDialog extends StatefulWidget {
  final String date;
  final int mealType;
  final List<Meal> recentMeals;

  /// 测试注入估算回调，避免单测发起真实网络请求
  final Future<({List<FoodEstimate> foods, String note})> Function(String name)?
      onEstimateForTest;

  const QuickLogMealDialog({
    super.key,
    required this.date,
    required this.mealType,
    this.recentMeals = const [],
    this.onEstimateForTest,
  });

  @override
  State<QuickLogMealDialog> createState() => _QuickLogMealDialogState();
}

class _QuickLogMealDialogState extends State<QuickLogMealDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  _QuickStep _step = _QuickStep.input;
  Meal? _draft;
  String? _aiNote;
  bool _matchedFromHistory = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Meal _cloneForCurrentSlot(Meal source) {
    return Meal(
      date: widget.date,
      mealType: widget.mealType,
      name: source.name.trim(),
      amount: source.amount,
      calories: Nutrition.clampMealCalories(source.calories),
      protein: Nutrition.clampMealMacro(source.protein),
      carbs: Nutrition.clampMealMacro(source.carbs),
      fat: Nutrition.clampMealMacro(source.fat),
    );
  }

  Meal? _findRecentMatch(String query) {
    final norm = query.trim().toLowerCase();
    if (norm.isEmpty) return null;
    for (final m in widget.recentMeals) {
      if (m.name.trim().toLowerCase() == norm) {
        return m;
      }
    }
    return null;
  }

  void _onTapRecent(Meal m) {
    Navigator.pop(
      context,
      QuickLogMealResult(
        path: QuickLogMealPath.reuseRecent,
        meal: _cloneForCurrentSlot(m),
      ),
    );
  }

  Future<void> _onNext() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      toast(context, context.l10n.mealEditNameRequired);
      return;
    }

    // 1) 优先匹配「最近吃过」中的同名记录（零网络延迟）
    final matched = _findRecentMatch(name);
    if (matched != null) {
      DebugServer.instance.log(
        'quick_log_diet matched history "$name" -> ${matched.calories.round()} kcal',
        tag: 'Diet',
      );
      setState(() {
        _draft = _cloneForCurrentSlot(matched);
        _aiNote = null;
        _matchedFromHistory = true;
        _step = _QuickStep.confirm;
      });
      return;
    }

    // 2) 未命中本地记录 -> 调用 AI 文字模型自动估算热量与三大营养素
    setState(() => _step = _QuickStep.estimating);
    try {
      final res = widget.onEstimateForTest != null
          ? await widget.onEstimateForTest!(name)
          : await AiService.estimateFoodText(name);
      if (!mounted) return;

      if (res.foods.isEmpty) {
        throw StateError('AI returned empty food estimate');
      }

      final totalKcal = res.foods.fold<double>(0, (s, f) => s + f.calories);
      final totalP = res.foods.fold<double>(0, (s, f) => s + f.protein);
      final totalC = res.foods.fold<double>(0, (s, f) => s + f.carbs);
      final totalF = res.foods.fold<double>(0, (s, f) => s + f.fat);
      final displayAmount = res.foods.length == 1
          ? res.foods.first.amount
          : res.foods.map((f) => f.name).join(' + ');

      DebugServer.instance.log(
        'quick_log_diet AI estimated "$name" -> ${totalKcal.round()} kcal (P:${totalP.round()} C:${totalC.round()} F:${totalF.round()})',
        tag: 'Diet',
      );
      setState(() {
        _draft = Meal(
          date: widget.date,
          mealType: widget.mealType,
          name: name,
          amount: displayAmount,
          calories: Nutrition.clampMealCalories(totalKcal),
          protein: Nutrition.clampMealMacro(totalP),
          carbs: Nutrition.clampMealMacro(totalC),
          fat: Nutrition.clampMealMacro(totalF),
        );
        _aiNote = res.note.trim().isEmpty ? null : res.note.trim();
        _matchedFromHistory = false;
        _step = _QuickStep.confirm;
      });
    } catch (e, st) {
      DebugServer.instance.logError(
        'Diet',
        e,
        st,
        'quick_log_diet AI estimate failed for "$name", falling back to full form',
      );
      if (!mounted) return;
      // 3) 历史匹配与 AI 估算均失败 -> 自动带着已输入名称回退完整 6 格表单
      Navigator.pop(
        context,
        QuickLogMealResult(
          path: QuickLogMealPath.openFullForm,
          meal: Meal(
            date: widget.date,
            mealType: widget.mealType,
            name: name,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
          ),
          fallbackError: e.toString(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _QuickStep.input => _buildStep1Input(context),
      _QuickStep.estimating => _buildEstimating(context),
      _QuickStep.confirm => _buildStep2Confirm(context),
    };
  }

  Widget _buildStep1Input(BuildContext context) {
    final l = context.l10n;
    final dietColor = AppColors.moduleDiet(context);
    final mealLabel = L10nHelper.mealTypeLabel(context, widget.mealType);
    final visibleRecent = widget.recentMeals.take(6).toList();

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, dietColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.restaurant_rounded, color: dietColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(l.quickMealTitle, style: AppTypography.sectionTitle(context)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.softBg(context, dietColor),
              borderRadius: AppRadius.bPill,
            ),
            child: Text(mealLabel, style: AppTypography.badge(context, color: dietColor)),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('quick_meal_name_input'),
                controller: _nameCtrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onNext(),
                decoration: InputDecoration(
                  hintText: l.quickMealHint,
                  prefixIcon: Icon(Icons.fastfood_rounded, color: dietColor, size: 20),
                ),
              ),
              if (visibleRecent.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l.quickMealRecentHeader,
                  style: AppTypography.caption(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < visibleRecent.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.xs),
                  _recentItemRow(context, visibleRecent[i], i, dietColor),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('quick_meal_cancel_btn'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton.icon(
          key: const ValueKey('quick_meal_next_btn'),
          onPressed: _onNext,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(l.quickMealNextBtn),
        ),
      ],
    );
  }

  Widget _recentItemRow(BuildContext context, Meal m, int index, Color accent) {
    return InkWell(
      key: ValueKey('quick_recent_meal_$index'),
      borderRadius: AppRadius.bMd,
      onTap: () => _onTapRecent(m),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle(context),
          borderRadius: AppRadius.bMd,
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Text(foodEmoji(m.name), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subtitle(context),
                  ),
                  Text(
                    'P ${fmtNum(m.protein)}g · C ${fmtNum(m.carbs)}g · F ${fmtNum(m.fat)}g',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context).copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${m.calories.round()} kcal',
              style: AppTypography.badge(context, color: accent),
            ),
            const SizedBox(width: 4),
            Icon(Icons.add_circle_outline_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimating(BuildContext context) {
    final l = context.l10n;
    final dietColor = AppColors.moduleDiet(context);
    return AlertDialog(
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: dietColor),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l.quickMealEstimating(_nameCtrl.text.trim()),
              style: AppTypography.body(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Confirm(BuildContext context) {
    final l = context.l10n;
    final draft = _draft!;
    final success = AppColors.success(context);
    final aiColor = AppColors.moduleAi(context);
    final badgeColor = _matchedFromHistory ? success : aiColor;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: badgeColor, size: 24),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(l.quickMealConfirmTitle, style: AppTypography.sectionTitle(context)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, badgeColor),
                  borderRadius: AppRadius.bPill,
                ),
                child: Text(
                  _matchedFromHistory ? l.quickMealSourceRecent : l.quickMealSourceAi,
                  style: AppTypography.badge(context, color: badgeColor),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SurfaceCard(
              padding: AppSpacing.cardCompactPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(foodEmoji(draft.name), style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(draft.name, style: AppTypography.cardTitle(context)),
                            if (draft.amount != null && draft.amount!.isNotEmpty)
                              Text(draft.amount!, style: AppTypography.caption(context)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${draft.calories.round()}',
                        key: const ValueKey('quick_meal_confirm_kcal'),
                        style: AppTypography.sectionTitle(
                          context,
                          color: AppColors.moduleDiet(context),
                        ).copyWith(fontSize: 28),
                      ),
                      const SizedBox(width: 4),
                      Text('kcal', style: AppTypography.bodySecondary(context)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.menuMacrosSummary(
                      fmtNum(draft.protein),
                      fmtNum(draft.carbs),
                      fmtNum(draft.fat),
                    ),
                    style: AppTypography.bodySecondary(context),
                  ),
                  if (_aiNote != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _aiNote!,
                      style: AppTypography.caption(context),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('quick_meal_edit_full_btn'),
          onPressed: () {
            Navigator.pop(
              context,
              QuickLogMealResult(
                path: QuickLogMealPath.openFullForm,
                meal: draft,
              ),
            );
          },
          child: Text(l.quickMealEditFullBtn),
        ),
        TextButton(
          key: const ValueKey('quick_meal_back_btn'),
          onPressed: () => setState(() => _step = _QuickStep.input),
          child: Text(l.quickMealBackBtn),
        ),
        FilledButton.icon(
          key: const ValueKey('quick_meal_confirm_save_btn'),
          onPressed: () {
            Navigator.pop(
              context,
              QuickLogMealResult(
                path: QuickLogMealPath.quickSave,
                meal: draft,
              ),
            );
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(l.quickMealSaveBtn),
        ),
      ],
    );
  }
}
