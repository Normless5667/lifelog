import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/targets.dart';
import '../../services/usage_telemetry_service.dart';
import '../../services/widget_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';
import 'food_confirm_sheet.dart';
import 'meal_edit_dialog.dart';

/// 饮食记录页（v2.0）：按日查看、按餐分组、拍照估算热量、文字描述估算、手动添加
class DietScreen extends StatefulWidget {
  const DietScreen({super.key});

  @override
  State<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends State<DietScreen> {
  String _date = today();
  List<Meal> _meals = [];
  DailyTargets _targets = const DailyTargets(2000, 100, 250, 55);
  bool _loading = true;
  bool _busyAi = false;

  @override
  void initState() {
    super.initState();
    Repo.dataVersion.addListener(_onRepoDataChanged);
    _load();
  }

  @override
  void dispose() {
    Repo.dataVersion.removeListener(_onRepoDataChanged);
    super.dispose();
  }

  void _onRepoDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final meals = await Repo.getMeals(_date);
    final targets = await DailyTargets.load(date: _date);
    WidgetService.sync(force: true);
    if (!mounted) return;
    setState(() {
      _meals = meals;
      _targets = targets;
      _loading = false;
    });
  }

  void _shiftDay(int delta) {
    final d = parseDate(_date).add(Duration(days: delta));
    setState(() => _date = fmtDate(d));
    _load();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseDate(_date),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (d != null) {
      setState(() => _date = fmtDate(d));
      _load();
    }
  }

  int _guessMealType() {
    final h = DateTime.now().hour;
    if (h < 10) return 0;
    if (h < 15) return 1;
    if (h < 21) return 2;
    return 3;
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  /// 拍照 / 相册 → 询问补充说明 → AI 识别 → 弹出确认编辑框
  Future<void> _photoEstimate(ImageSource source, {int? defaultMealType}) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 82,
      );
    } catch (e) {
      if (!mounted) return;
      toast(context, context.l10n.dietCameraError('$e'));
      return;
    }
    if (picked == null || !mounted) return;

    final hint = await _askPhotoHint(File(picked.path));
    if (hint == null || !mounted) return;

    setState(() => _busyAi = true);
    try {
      final res = await AiService.analyzeFoodImage(File(picked.path), hint: hint);
      if (!mounted) return;
      setState(() => _busyAi = false);
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FoodConfirmSheet(
          date: _date,
          initialMealType: defaultMealType ?? _guessMealType(),
          estimates: res.foods,
          aiNote: res.note,
          photoPath: picked!.path,
        ),
      );
      if (saved == true) _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAi = false);
      showAiError(context, e, onOpenSettings: _openSettings);
    }
  }

  Future<String?> _askPhotoHint(File img) async {
    final l = context.l10n;
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dietPhotoHintTitle, style: AppTypography.sectionTitle(ctx)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: AppRadius.bMd,
                child: Image.file(img, height: 180, cacheHeight: 540, fit: BoxFit.cover),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: l.dietPhotoHintLabel,
                  hintText: l.dietPhotoHintPlaceholder,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            icon: const Icon(Icons.auto_awesome_rounded, size: 17),
            label: Text(l.dietStartAnalyze),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  /// 文字描述估算热量
  Future<void> _textEstimate({int? defaultMealType}) async {
    final l = context.l10n;
    final ctrl = TextEditingController();
    final desc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dietTextEstimateTitle, style: AppTypography.sectionTitle(ctx)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: l.dietTextEstimateHint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(l.dietEstimateBtn),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (desc == null || !mounted) return;

    setState(() => _busyAi = true);
    try {
      final res = await AiService.estimateFoodText(desc);
      if (!mounted) return;
      setState(() => _busyAi = false);
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FoodConfirmSheet(
          date: _date,
          initialMealType: defaultMealType ?? _guessMealType(),
          estimates: res.foods,
          aiNote: res.note,
        ),
      );
      if (saved == true) _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAi = false);
      showAiError(context, e, onOpenSettings: _openSettings);
    }
  }

  Future<void> _manualEdit({Meal? existing, int? defaultMealType}) async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    UsageTelemetryService.instance.trackFeature('quick_log_diet', 'tap');
    final recentMeals = existing == null ? await Repo.getRecentUniqueMeals(days: 7, limit: 6) : const <Meal>[];
    if (!mounted) return;
    final m = await showDialog<Meal>(
      context: context,
      builder: (_) => MealEditDialog(
        date: _date,
        existing: existing,
        initialMealType: defaultMealType ?? _guessMealType(),
        recentMeals: recentMeals,
      ),
    );
    final dur = DateTime.now().millisecondsSinceEpoch - t0;
    if (m != null) {
      await Repo.saveMeal(m);
      UsageTelemetryService.instance.trackFeature('quick_log_diet', 'success', durationMs: dur);
      _load();
    } else {
      UsageTelemetryService.instance.trackFeature('quick_log_diet', 'cancel', durationMs: dur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final totals = DayTotals.of(_meals);
    final dietColor = AppColors.moduleDiet(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.chevron_left_rounded, color: AppColors.textPrimary(context)),
              onPressed: () => _shiftDay(-1),
            ),
            InkWell(
              onTap: _pickDate,
              borderRadius: AppRadius.bMd,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, dietColor, lightAlpha: 0.10, darkAlpha: 0.16),
                  borderRadius: AppRadius.bPill,
                  border: Border.all(color: AppColors.softBorder(context, dietColor)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 13, color: dietColor),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      L10nHelper.friendlyDateL10n(context, _date),
                      style: AppTypography.subtitle(context, color: dietColor),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.chevron_right_rounded, color: AppColors.textPrimary(context)),
              onPressed: () => _shiftDay(1),
            ),
          ],
        ),
        actions: [
          if (_date != today())
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.surfaceSubtle(context),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                ),
                onPressed: () {
                  setState(() => _date = today());
                  _load();
                },
                child: Text(l.commonToday),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            ListView.builder(
              padding: AppSpacing.pagePadding,
              itemCount: 6, // 0: summary, 1: quick actions, 2..5: 4 meal sections
              itemBuilder: (_, idx) {
                if (idx == 0) {
                  return CalorieSummaryCard(totals: totals, targets: _targets);
                }
                if (idx == 1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: _quickActionRow(),
                  );
                }
                return _mealSection(idx - 2);
              },
            ),
          if (_busyAi)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                    vertical: AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: dietColor),
                      const SizedBox(height: AppSpacing.lg),
                      Text(l.dietAiAnalyzing, style: AppTypography.subtitle(context)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 三栏等宽快捷估算入口（统一圆角与低饱和色底，适配 360dp 英文不溢出）
  Widget _quickActionRow() {
    final l = context.l10n;
    final dietColor = AppColors.moduleDiet(context);
    final scheduleColor = AppColors.moduleSchedule(context);
    final aiColor = AppColors.moduleAi(context);

    Widget tile({
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: ScaleTap(
          onTap: onTap,
          borderRadius: AppRadius.bLg,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: AppRadius.bLg,
              border: Border.all(color: AppColors.border(context)),
              boxShadow: AppShadows.subtle(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, color, lightAlpha: 0.12, darkAlpha: 0.18),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  label,
                  style: AppTypography.badge(context, color: AppColors.textPrimary(context))
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(
          icon: Icons.camera_alt_rounded,
          label: l.dietScanFood,
          color: dietColor,
          onTap: () => _photoEstimate(ImageSource.camera),
        ),
        const SizedBox(width: AppSpacing.sm),
        tile(
          icon: Icons.photo_library_rounded,
          label: l.dietPickGallery,
          color: scheduleColor,
          onTap: () => _photoEstimate(ImageSource.gallery),
        ),
        const SizedBox(width: AppSpacing.sm),
        tile(
          icon: Icons.auto_awesome_rounded,
          label: l.dietAiTextEstimate,
          color: aiColor,
          onTap: _textEstimate,
        ),
      ],
    );
  }

  static const _mealIcons = <IconData>[
    Icons.wb_twilight_rounded,
    Icons.wb_sunny_rounded,
    Icons.nights_stay_rounded,
    Icons.icecream_rounded,
  ];

  Color _mealColor(BuildContext context, int mealType) {
    switch (mealType) {
      case 0:
        return AppColors.warning(context);
      case 1:
        return AppColors.moduleDiet(context);
      case 2:
        return AppColors.primary(context);
      default:
        return AppColors.teal(context);
    }
  }

  Widget _mealSection(int mealType) {
    final l = context.l10n;
    final items = _meals.where((m) => m.mealType == mealType).toList();
    final subKcal = items.fold<double>(0, (s, m) => s + m.calories);
    final mealColor = _mealColor(context, mealType);
    final mealLabel = L10nHelper.mealTypeLabel(context, mealType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          '$mealLabel${subKcal > 0 ? ' · ${fmtNum(subKcal)} kcal' : ''}',
          icon: _mealIcons[mealType],
          iconColor: mealColor,
          trailing: TextButton.icon(
            onPressed: () => _manualEdit(defaultMealType: mealType),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
            label: Text(l.dietManualAdd),
          ),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: items.isEmpty
              ? InkWell(
                  onTap: () => _manualEdit(defaultMealType: mealType),
                  borderRadius: AppRadius.bXl,
                  child: Padding(
                    padding: AppSpacing.cardCompactPadding,
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.softBg(context, mealColor),
                            borderRadius: AppRadius.bMd,
                          ),
                          child: Icon(_mealIcons[mealType], color: mealColor, size: 19),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            l.dietEmptyMealHint(mealLabel),
                            style: AppTypography.bodySecondary(context),
                          ),
                        ),
                        Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: AppColors.textTertiary(context),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _mealRow(items[i], mealColor),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _mealRow(Meal m, Color mealColor) {
    final l = context.l10n;
    final hasPhoto = m.photoPath != null && File(m.photoPath!).existsSync();
    return InkWell(
      onTap: () => _manualEdit(existing: m),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (hasPhoto)
              ClipRRect(
                borderRadius: AppRadius.bMd,
                child: Image.file(
                  File(m.photoPath!),
                  width: 44,
                  height: 44,
                  cacheWidth: 132,
                  cacheHeight: 132,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, mealColor),
                  borderRadius: AppRadius.bMd,
                ),
                child: Text(foodEmoji(m.name), style: const TextStyle(fontSize: 21)),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m.name}${m.amount?.isNotEmpty == true ? ' · ${m.amount}' : ''}',
                    style: AppTypography.subtitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'P ${fmtNum(m.protein)}g · C ${fmtNum(m.carbs)}g · F ${fmtNum(m.fat)}g',
                    style: AppTypography.caption(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.softBg(context, mealColor),
                borderRadius: AppRadius.bSm,
              ),
              child: Text(
                '${fmtNum(m.calories)} kcal',
                style: AppTypography.badge(context, color: mealColor),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: AppColors.textTertiary(context),
              ),
              onPressed: () async {
                if (await confirm(context, l.dietDeleteMealConfirm(m.name))) {
                  await Repo.deleteMeal(m.id!);
                  _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
