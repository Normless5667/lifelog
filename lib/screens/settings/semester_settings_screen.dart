import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/academic_calendar_service.dart';
import '../../services/holiday_service.dart';
import '../../services/reminder_service.dart';
import '../../services/widget_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';

/// 学期与学术日历设置页（v3.0.1）：
/// - 普通用户可直接填「学期名称 / 第 1 周开始日期 / 总周数」保存即生效
/// - 支持切换 academic_calendar.json 里的秋季/春季学期
/// - 支持对 confidence=low 的校历红格子逐条手动修正（非教学日 / 设为假期 / 正常上课）
/// - 高级区支持粘贴导入学术日历 JSON，并预留 iCal (.ics) 入口
class SemesterSettingsScreen extends StatefulWidget {
  final AcademicTerm? initialTermForTest;
  final AcademicCalendar? initialCalendarForTest;
  final DateTime? nowForTest;
  final Future<void> Function(ManualSemesterConfig cfg)? onSaveOverrideForTest;

  const SemesterSettingsScreen({
    super.key,
    this.initialTermForTest,
    this.initialCalendarForTest,
    this.nowForTest,
    this.onSaveOverrideForTest,
  });

  @override
  State<SemesterSettingsScreen> createState() => _SemesterSettingsScreenState();
}

class _SemesterSettingsScreenState extends State<SemesterSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _weeksCtrl = TextEditingController();

  DateTime _week1Start = DateTime(2026, 9, 28);
  int _totalWeeks = 12;
  String? _selectedTermId;
  AcademicCalendar? _calendar;
  AcademicTerm? _activeTerm;
  Map<String, LowConfidenceOverride> _lowOverrides = const {};
  bool _hasCustomCalendar = false;
  bool _loading = true;

  DateTime get _now => widget.nowForTest ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _weeksCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.initialTermForTest != null) {
      final term = widget.initialTermForTest!;
      final cal = widget.initialCalendarForTest ??
          AcademicCalendar(
            schemaVersion: 1,
            source: 'test',
            institution: 'test',
            academicYear: '2026/2027',
            terms: [term],
          );
      if (!mounted) return;
      final isEn = WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en';
      setState(() {
        _calendar = cal;
        _activeTerm = term;
        _selectedTermId = term.id;
        _week1Start = mondayOf(term.week1Start);
        _totalWeeks = term.totalWeeks;
        _nameCtrl.text = term.localizedName(isEn: isEn);
        _weeksCtrl.text = '${term.totalWeeks}';
        _lowOverrides = const {};
        _hasCustomCalendar = false;
        _loading = false;
      });
      return;
    }

    final cal = await AcademicCalendarService.loadCalendar();
    final term = await AcademicCalendarService.getActiveTerm(now: _now);
    final manual = await AcademicCalendarService.getManualConfig();
    final lowOv = await AcademicCalendarService.getLowConfidenceOverrides();
    final hasCustom = await AcademicCalendarService.hasCustomCalendar();
    if (!mounted) return;
    final isEn = context.isEnLocale;
    setState(() {
      _calendar = cal;
      _activeTerm = term;
      _selectedTermId = manual?.selectedTermId ?? term.id;
      _week1Start = mondayOf(term.week1Start);
      _totalWeeks = term.totalWeeks;
      _nameCtrl.text = manual != null && manual.name.isNotEmpty
          ? manual.name
          : term.localizedName(isEn: isEn);
      _weeksCtrl.text = '${term.totalWeeks}';
      _lowOverrides = Map<String, LowConfidenceOverride>.from(lowOv);
      _hasCustomCalendar = hasCustom;
      _loading = false;
    });
  }

  Future<void> _pickWeek1Start() async {
    final l = context.l10n;
    final picked = await showDatePicker(
      context: context,
      initialDate: _week1Start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: l.schedulePickSemesterStartHelp,
    );
    if (picked == null || !mounted) return;
    setState(() => _week1Start = mondayOf(picked));
  }

  void _updateWeeks(int v) {
    final clamped = v.clamp(1, 30);
    setState(() {
      _totalWeeks = clamped;
      _weeksCtrl.text = '$clamped';
    });
  }

  Future<void> _saveManual() async {
    final l = context.l10n;
    final parsedWeeks = int.tryParse(_weeksCtrl.text.trim()) ?? _totalWeeks;
    final clampedWeeks = parsedWeeks.clamp(1, 30);
    final name = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : (_activeTerm?.localizedName(isEn: context.isEnLocale) ?? 'Semester');

    final cfg = ManualSemesterConfig(
      name: name,
      week1Start: mondayOf(_week1Start),
      totalWeeks: clampedWeeks,
      selectedTermId: _selectedTermId,
    );

    if (widget.onSaveOverrideForTest != null) {
      await widget.onSaveOverrideForTest!(cfg);
      if (!mounted) return;
      toast(context, l.semesterSavedToast);
      Navigator.pop(context, true);
      return;
    }

    await AcademicCalendarService.saveManualConfig(cfg);
    HolidayService.clearMemoryCache();
    ReminderService.syncAlarms();
    WidgetService.sync(force: true);
    if (!mounted) return;
    toast(context, l.semesterSavedToast);
    Navigator.pop(context, true);
  }

  Future<void> _applyCalendarTerm(AcademicTerm term) async {
    final isEn = context.isEnLocale;
    setState(() {
      _selectedTermId = term.id;
      _activeTerm = term;
      _week1Start = mondayOf(term.week1Start);
      _totalWeeks = term.totalWeeks;
      _nameCtrl.text = term.localizedName(isEn: isEn);
      _weeksCtrl.text = '${term.totalWeeks}';
    });
  }

  Future<void> _autoMatchTerm() async {
    if (widget.onSaveOverrideForTest == null) {
      await AcademicCalendarService.clearManualConfig();
      HolidayService.clearMemoryCache();
      ReminderService.syncAlarms();
      WidgetService.sync(force: true);
    }
    await _load();
    if (!mounted) return;
    toast(context, context.l10n.semesterSavedToast);
  }

  Future<void> _openJsonImportDialog() async {
    final l = context.l10n;
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.scheduleImportCalendarTitle, style: AppTypography.sectionTitle(ctx)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: l.semesterImportJsonHint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(l.commonSave),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (raw == null || !mounted) return;
    try {
      final cal = await AcademicCalendarService.importCalendarJson(raw);
      HolidayService.clearMemoryCache();
      ReminderService.syncAlarms();
      WidgetService.sync(force: true);
      await _load();
      if (!mounted) return;
      toast(context, l.semesterImportSuccessToast(cal.terms.length));
    } catch (e) {
      if (!mounted) return;
      toast(context, l.semesterImportErrorToast('$e'));
    }
  }

  Future<void> _resetBuiltinCalendar() async {
    await AcademicCalendarService.resetToBuiltinCalendar();
    HolidayService.clearMemoryCache();
    ReminderService.syncAlarms();
    WidgetService.sync(force: true);
    await _load();
    if (!mounted) return;
    toast(context, context.l10n.semesterResetBuiltinToast);
  }

  String _previewLabel() {
    final l = context.l10n;
    final w = weekOfSemester(_week1Start, _now);
    final end = mondayOf(_week1Start).add(Duration(days: _totalWeeks * 7 - 1));
    if (w < 1) {
      return l.semesterPreviewBefore(fmtDate(mondayOf(_week1Start)));
    }
    if (w > _totalWeeks) {
      return l.semesterPreviewAfter(_totalWeeks);
    }
    return l.semesterPreviewCurrent(w, fmtDate(mondayOf(_week1Start)), fmtDate(end));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheduleColor = AppColors.moduleSchedule(context);
    final teal = AppColors.teal(context);
    final warning = AppColors.warning(context);
    final isEn = context.isEnLocale;

    final lowConfEntries = (_activeTerm?.holidays ?? const <CalendarHolidayEntry>[])
        .where((h) => h.confidence == CalendarHolidayConfidence.low)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.semesterSettingsTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                SectionTitle(
                  l.semesterBasicSection,
                  icon: Icons.event_note_rounded,
                  iconColor: scheduleColor,
                ),
                SurfaceCard(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('semester_name_field'),
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: l.semesterNameLabel,
                          hintText: l.semesterNameHint,
                          prefixIcon: const Icon(Icons.school_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      InkWell(
                        key: const ValueKey('semester_start_picker'),
                        borderRadius: AppRadius.bMd,
                        onTap: _pickWeek1Start,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle(context),
                            borderRadius: AppRadius.bMd,
                            border: Border.all(color: AppColors.border(context)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 18, color: scheduleColor),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.semesterWeek1StartLabel,
                                      style: AppTypography.caption(context),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      fmtDate(_week1Start),
                                      style: AppTypography.cardTitle(context),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.edit_calendar_rounded,
                                size: 20,
                                color: AppColors.textSecondary(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('semester_total_weeks_field'),
                              controller: _weeksCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: l.semesterTotalWeeksLabel,
                                suffixText: l.semesterTotalWeeksSuffix,
                                prefixIcon: const Icon(Icons.date_range_rounded, size: 18),
                              ),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n >= 1 && n <= 30) {
                                  setState(() => _totalWeeks = n);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton.outlined(
                            onPressed: _totalWeeks > 1 ? () => _updateWeeks(_totalWeeks - 1) : null,
                            icon: const Icon(Icons.remove_rounded, size: 18),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          IconButton.outlined(
                            onPressed: _totalWeeks < 30 ? () => _updateWeeks(_totalWeeks + 1) : null,
                            icon: const Icon(Icons.add_rounded, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softBg(context, scheduleColor),
                          borderRadius: AppRadius.bMd,
                          border: Border.all(color: AppColors.softBorder(context, scheduleColor)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: scheduleColor),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _previewLabel(),
                                style: AppTypography.body(context, color: scheduleColor)
                                    .copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.icon(
                        key: const ValueKey('semester_save_btn'),
                        onPressed: _saveManual,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: Text(l.semesterSaveBtn),
                      ),
                    ],
                  ),
                ),
                if (_calendar != null && _calendar!.terms.isNotEmpty) ...[
                  SectionTitle(
                    l.semesterTermsSection,
                    icon: Icons.swap_horiz_rounded,
                    iconColor: teal,
                  ),
                  SurfaceCard(
                    padding: AppSpacing.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final term in _calendar!.terms)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppRadius.bMd,
                                  side: BorderSide(
                                    color: term.id == _selectedTermId
                                        ? AppColors.softBorder(context, scheduleColor)
                                        : AppColors.border(context),
                                  ),
                                ),
                                tileColor: term.id == _selectedTermId
                                    ? AppColors.softBg(context, scheduleColor)
                                    : null,
                                leading: Icon(
                                  term.id == _selectedTermId
                                      ? Icons.check_circle_rounded
                                      : Icons.calendar_month_rounded,
                                  color: term.id == _selectedTermId
                                      ? scheduleColor
                                      : AppColors.textSecondary(context),
                                ),
                                title: Text(
                                  term.localizedName(isEn: isEn),
                                  style: AppTypography.cardTitle(context),
                                ),
                                subtitle: Text(
                                  l.semesterTermItemSub(
                                    fmtDate(term.week1Start),
                                    term.totalWeeks,
                                  ),
                                  style: AppTypography.bodySecondary(context),
                                ),
                                onTap: () => _applyCalendarTerm(term),
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _autoMatchTerm,
                            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                            label: Text(l.semesterAutoTermBtn),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (lowConfEntries.isNotEmpty) ...[
                  SectionTitle(
                    l.semesterLowConfSection,
                    icon: Icons.help_outline_rounded,
                    iconColor: warning,
                  ),
                  SurfaceCard(
                    padding: AppSpacing.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.semesterLowConfDesc,
                          style: AppTypography.bodySecondary(context),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final item in lowConfEntries) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.date} · ${l.scheduleNonTeachingLabel}',
                                  style: AppTypography.cardTitle(context),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                SegmentedButton<LowConfidenceOverride>(
                                  showSelectedIcon: false,
                                  segments: [
                                    ButtonSegment(
                                      value: LowConfidenceOverride.neutral,
                                      label: Text(
                                        l.semesterLowConfNeutral,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: LowConfidenceOverride.holiday,
                                      label: Text(
                                        l.semesterLowConfHoliday,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: LowConfidenceOverride.normal,
                                      label: Text(
                                        l.semesterLowConfNormal,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                  selected: {
                                    _lowOverrides[item.date] ?? LowConfidenceOverride.neutral,
                                  },
                                  onSelectionChanged: (sel) async {
                                    final next = sel.first;
                                    setState(() => _lowOverrides[item.date] = next);
                                    if (widget.onSaveOverrideForTest == null) {
                                      await AcademicCalendarService.setLowConfidenceOverride(
                                        item.date,
                                        next,
                                      );
                                      HolidayService.clearMemoryCache();
                                      ReminderService.syncAlarms();
                                      WidgetService.sync(force: true);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                SectionTitle(
                  l.semesterAdvancedSection,
                  icon: Icons.data_object_rounded,
                  iconColor: scheduleColor,
                ),
                SurfaceCard(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _openJsonImportDialog,
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: Text(l.semesterImportJsonBtn),
                      ),
                      if (_hasCustomCalendar) ...[
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _resetBuiltinCalendar,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(l.semesterResetBuiltinBtn),
                        ),
                      ],
                      const Divider(height: 24),
                      // 预留 iCal (.ics) 导入入口（P2，后续版本扩展）
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          enabled: false,
                          leading: Icon(
                            Icons.event_available_rounded,
                            color: AppColors.textTertiary(context),
                          ),
                          title: Text(
                            l.semesterIcalSoonTitle,
                            style: AppTypography.body(
                              context,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                          subtitle: Text(
                            l.semesterIcalSoonSub,
                            style: AppTypography.caption(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
