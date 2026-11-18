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

/// 饮食记录页：按日查看、按餐分组、拍照估算热量、文字描述估算、手动添加
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
    _load();
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
        title: Text(l.dietPhotoHintTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(img, height: 180, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
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
            icon: const Icon(Icons.auto_awesome),
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
        title: Text(l.dietTextEstimateTitle),
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
    final m = await showDialog<Meal>(
      context: context,
      builder: (_) => MealEditDialog(
        date: _date,
        existing: existing,
        initialMealType: defaultMealType ?? _guessMealType(),
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftDay(-1)),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(L10nHelper.friendlyDateL10n(context, _date)),
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shiftDay(1)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_date != today())
            TextButton(
              onPressed: () {
                setState(() => _date = today());
                _load();
              },
              child: Text(l.commonToday),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              children: [
                CalorieSummaryCard(totals: totals, targets: _targets),
                const SizedBox(height: 8),
                _quickActionRow(),
                for (var t = 0; t < 4; t++) _mealSection(t),
              ],
            ),
          if (_busyAi)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(l.dietAiAnalyzing),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickActionRow() {
    final l = context.l10n;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _photoEstimate(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(l.dietScanFood),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => _photoEstimate(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(l.dietPickGallery),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _textEstimate,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(l.dietAiTextEstimate),
          ),
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

  static const _mealColors = <Color>[
    Color(0xFFFFA726),
    Color(0xFFEF5350),
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
  ];

  Widget _mealSection(int mealType) {
    final l = context.l10n;
    final items = _meals.where((m) => m.mealType == mealType).toList();
    final subKcal = items.fold<double>(0, (s, m) => s + m.calories);
    final mealColor = _mealColors[mealType];
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
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: Text(l.dietManualAdd),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: items.isEmpty
              ? ListTile(
                  leading: CircleAvatar(
                    backgroundColor: mealColor.withValues(alpha: 0.14),
                    child: Icon(_mealIcons[mealType], color: mealColor, size: 20),
                  ),
                  title: Text(
                    l.dietEmptyMealHint(mealLabel),
                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                  ),
                  onTap: () => _manualEdit(defaultMealType: mealType),
                )
              : Column(
                  children: items.map((m) {
                    final hasPhoto = m.photoPath != null && File(m.photoPath!).existsSync();
                    return ListTile(
                      leading: hasPhoto
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(File(m.photoPath!), width: 48, height: 48, fit: BoxFit.cover),
                            )
                          : Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: mealColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(foodEmoji(m.name), style: const TextStyle(fontSize: 22)),
                            ),
                      title: Text(
                        '${m.name}${m.amount?.isNotEmpty == true ? ' · ${m.amount}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'P ${fmtNum(m.protein)}g  ·  C ${fmtNum(m.carbs)}g  ·  F ${fmtNum(m.fat)}g',
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: mealColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${fmtNum(m.calories)} kcal',
                              style: TextStyle(fontWeight: FontWeight.bold, color: mealColor, fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              if (await confirm(context, l.dietDeleteMealConfirm(m.name))) {
                                await Repo.deleteMeal(m.id!);
                                _load();
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () => _manualEdit(existing: m),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}
