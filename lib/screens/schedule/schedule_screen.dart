import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/database.dart';
import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/academic_calendar_service.dart';
import '../../services/ai_service.dart';
import '../../services/holiday_service.dart';
import '../../services/reminder_service.dart';
import '../../services/weather_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../settings/notification_diagnostics_screen.dart';
import '../settings/semester_settings_screen.dart';
import '../settings/settings_screen.dart';
import 'bus_schedule_screen.dart';
import 'course_edit_screen.dart';

/// 周视图课表（v3.0.1：PageView 左右滑动切周 + 学术日历周数 + 学期边界 + 今日快捷跳转）
class ScheduleScreen extends StatefulWidget {
  final DateTime? nowForTest;
  final AcademicTerm? initialTermForTest;
  final List<Course>? initialCoursesForTest;
  final Map<String, HolidayInfo>? initialHolidaysForTest;
  final Map<String, CalendarHolidayEntry>? initialNonTeachingForTest;

  const ScheduleScreen({
    super.key,
    this.nowForTest,
    this.initialTermForTest,
    this.initialCoursesForTest,
    this.initialHolidaysForTest,
    this.initialNonTeachingForTest,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _cellHeight = 60.0;
  static const _leftWidth = 30.0;
  static const int _minWeek = -4;

  List<Course> _courses = [];
  AcademicTerm _activeTerm = AcademicCalendarService.defaultFallbackTerm;
  int _sections = 12;
  int _currentWeek = 1;
  int _week = 1;
  bool _loading = true;
  bool _busyAi = false;
  WeatherInfo? _weather;
  final Map<int, Map<String, HolidayInfo>> _holidaysByWeek = {};
  final Map<int, Map<String, CalendarHolidayEntry>> _nonTeachingByWeek = {};
  PageController? _pageCtrl;

  static bool _seedPromptOpen = false;

  DateTime get _now => widget.nowForTest ?? DateTime.now();
  DateTime get _semesterStart => _activeTerm.week1Start;
  int get _maxWeek => math.max(_activeTerm.totalWeeks + 8, 24);
  int get _pageCount => _maxWeek - _minWeek + 1;
  int _pageToWeek(int page) => _minWeek + page;
  int _weekToPage(int week) => (week - _minWeek).clamp(0, _pageCount - 1);

  @override
  void initState() {
    super.initState();
    Repo.dataVersion.addListener(_onRepoDataChanged);
    _load(resetWeek: true);
  }

  @override
  void dispose() {
    Repo.dataVersion.removeListener(_onRepoDataChanged);
    _pageCtrl?.dispose();
    super.dispose();
  }

  void _onRepoDataChanged() {
    if (mounted) _load();
  }

  void _ensurePageController(int targetWeek) {
    final targetPage = _weekToPage(targetWeek);
    if (_pageCtrl == null) {
      _pageCtrl = PageController(initialPage: targetPage);
      return;
    }
    if (_pageCtrl!.hasClients) {
      final cur = _pageCtrl!.page?.round();
      if (cur != targetPage) {
        _pageCtrl!.jumpToPage(targetPage);
      }
    }
  }

  void _animateToWeek(int targetWeek) {
    final clamped = targetWeek.clamp(_minWeek, _maxWeek);
    final targetPage = _weekToPage(clamped);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_pageCtrl != null && _pageCtrl!.hasClients) {
      if (reduceMotion || (clamped - _week).abs() > 4) {
        _pageCtrl!.jumpToPage(targetPage);
      } else {
        _pageCtrl!.animateToPage(
          targetPage,
          duration: AppMotion.medium1,
          curve: AppMotion.standardCurve,
        );
      }
    }
    if (_week != clamped) {
      setState(() => _week = clamped);
    }
    _loadWeekMarkers(clamped, prefetchNeighbors: true);
  }

  Future<void> _loadWeekMarkers(
    int targetWeek, {
    AcademicTerm? termOverride,
    bool prefetchNeighbors = false,
  }) async {
    final term = termOverride ?? _activeTerm;
    final weeksToFetch = prefetchNeighbors
        ? <int>[targetWeek, targetWeek - 1, targetWeek + 1]
        : <int>[targetWeek];

    for (final w in weeksToFetch) {
      if (w < _minWeek || w > _maxWeek) continue;
      final monday = term.weekStartDate(w);
      final sunday = term.weekEndDate(w);
      final Map<String, HolidayInfo> holidays;
      final Map<String, CalendarHolidayEntry> nonTeaching;

      if (widget.initialHolidaysForTest != null || widget.initialNonTeachingForTest != null) {
        final sStr = fmtDate(monday);
        final eStr = fmtDate(sunday);
        holidays = Map<String, HolidayInfo>.from(widget.initialHolidaysForTest ?? const {})
          ..removeWhere((k, _) => k.compareTo(sStr) < 0 || k.compareTo(eStr) > 0);
        nonTeaching = Map<String, CalendarHolidayEntry>.from(
          widget.initialNonTeachingForTest ?? const {},
        )..removeWhere((k, _) => k.compareTo(sStr) < 0 || k.compareTo(eStr) > 0);
      } else {
        holidays = await HolidayService.getHolidaysForRange(monday, sunday);
        nonTeaching = await AcademicCalendarService.getNonTeachingDaysInRange(monday, sunday);
        // 若某天已被确认为假期，则不再重复显示中性非教学日标记
        nonTeaching.removeWhere((k, _) => holidays.containsKey(k));
      }

      if (!mounted) return;
      setState(() {
        _holidaysByWeek[w] = holidays;
        _nonTeachingByWeek[w] = nonTeaching;
      });
    }
  }

  Future<void> _load({bool resetWeek = false}) async {
    if (widget.initialTermForTest != null) {
      final term = widget.initialTermForTest!;
      final courses = widget.initialCoursesForTest ?? const <Course>[];
      final currentWeek = term.weekOfDate(_now);
      final displayWeek = resetWeek ? currentWeek : _week;
      final clampedDisplay = displayWeek.clamp(_minWeek, math.max(term.totalWeeks + 8, 24)).toInt();
      _holidaysByWeek.clear();
      _nonTeachingByWeek.clear();
      _activeTerm = term;
      _ensurePageController(clampedDisplay);
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _sections = 12;
        _currentWeek = currentWeek;
        _week = clampedDisplay;
        _loading = false;
      });
      await _loadWeekMarkers(clampedDisplay, termOverride: term, prefetchNeighbors: true);
      return;
    }

    final courses = await Repo.getCourses();
    final term = await AcademicCalendarService.getActiveTerm(now: _now);
    final sections = await Repo.getSectionsPerDay();
    final weather = await WeatherService.getWeather();
    final currentWeek = term.weekOfDate(_now);
    final maxW = math.max(term.totalWeeks + 8, 24);
    final displayWeek = (resetWeek ? currentWeek : _week).clamp(_minWeek, maxW).toInt();
    final prompted = await Repo.hasCourseSeedPrompted();
    if (!mounted) return;
    _holidaysByWeek.clear();
    _nonTeachingByWeek.clear();
    _activeTerm = term;
    _ensurePageController(displayWeek);
    setState(() {
      _courses = courses;
      _sections = sections;
      _weather = weather;
      _currentWeek = currentWeek;
      _week = displayWeek;
      _loading = false;
    });
    await _loadWeekMarkers(displayWeek, termOverride: term, prefetchNeighbors: true);
    ReminderService.syncAlarms();
    if (courses.isEmpty && !prompted && !_seedPromptOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePromptSeedSample();
      });
    }
  }

  /// 全新安装首次进入空课表时询问是否导入 BUV 示例课表
  Future<void> _maybePromptSeedSample() async {
    if (_seedPromptOpen || !mounted) return;
    _seedPromptOpen = true;
    try {
      final l = context.l10n;
      final importSample = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l.scheduleSeedPromptTitle, style: AppTypography.sectionTitle(ctx)),
          content: Text(l.scheduleSeedPromptDesc, style: AppTypography.body(ctx)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.scheduleSeedSkipBtn),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.school_rounded, size: 17),
              label: Text(l.scheduleSeedImportBtn),
            ),
          ],
        ),
      );
      if (importSample == true) {
        final count = await Repo.importBuiltinSampleCourses();
        if (mounted) {
          toast(context, context.l10n.scheduleImportedToast(count));
          _load();
        }
      } else {
        await Repo.setCourseSeedPrompted();
      }
    } finally {
      _seedPromptOpen = false;
    }
  }

  /// 二次确认清空全部课程并取消对应上课提醒闹钟
  Future<void> _confirmClearAllCourses() async {
    final l = context.l10n;
    if (_courses.isEmpty) {
      toast(context, l.scheduleAlreadyEmptyToast);
      return;
    }
    final count = _courses.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.scheduleClearConfirmTitle, style: AppTypography.sectionTitle(ctx)),
        content: Text(l.scheduleClearConfirmDesc(count), style: AppTypography.body(ctx)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger(ctx),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.scheduleClearConfirmBtn),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await Repo.clearAllCourses();
    if (!mounted) return;
    toast(context, l.scheduleClearedToast(deleted));
    _load();
  }

  Future<void> _edit({Course? course, int? weekday, int? section}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CourseEditScreen(
          course: course,
          initialWeekday: weekday,
          initialSection: section,
          sectionsPerDay: _sections,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openImportMenu() async {
    final l = context.l10n;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l.scheduleImportTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(l.scheduleImportSub),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(l.scheduleImportPresetTitle),
              subtitle: Text(l.scheduleImportPresetSub),
              onTap: () => Navigator.pop(ctx, 'preset'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.scheduleImportGalleryTitle),
              subtitle: Text(l.scheduleImportGallerySub),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(l.scheduleImportCameraTitle),
              subtitle: Text(l.scheduleImportCameraSub),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: Text(l.scheduleImportTextTitle),
              subtitle: Text(l.scheduleImportTextSub),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: Text(l.scheduleImportCalendarTitle),
              subtitle: Text(l.scheduleImportCalendarSub),
              onTap: () => Navigator.pop(ctx, 'calendar_json'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'preset') {
      final preset = AppDatabase.defaultScheduleCourses
          .map((m) => Course.fromMap({...m, 'source': Course.sourceBuiltin}))
          .toList();
      await _confirmImportCourses(preset);
    } else if (action == 'gallery') {
      await _importFromImage(ImageSource.gallery);
    } else if (action == 'camera') {
      await _importFromImage(ImageSource.camera);
    } else if (action == 'text') {
      await _importFromText();
    } else if (action == 'calendar_json') {
      await _openSemesterSettings();
    }
  }

  Future<void> _openSemesterSettings() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SemesterSettingsScreen()),
    );
    if (changed == true && mounted) {
      await _load(resetWeek: true);
    } else if (mounted) {
      await _load();
    }
  }

  Future<void> _importFromImage(ImageSource src) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 88);
    } catch (e) {
      if (!mounted) return;
      toast(context, context.l10n.dietCameraError('$e'));
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _busyAi = true);
    try {
      final parsed = await AiService.parseScheduleImage(File(picked.path));
      if (!mounted) return;
      setState(() => _busyAi = false);
      await _confirmImportCourses(parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAi = false);
      showAiError(
        context,
        e,
        onOpenSettings: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      );
    }
  }

  Future<void> _importFromText() async {
    final l = context.l10n;
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.schedulePasteDialogTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: l.schedulePasteDialogHint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(l.scheduleAiParseBtn),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (raw == null || !mounted) return;

    setState(() => _busyAi = true);
    try {
      final parsed = await AiService.parseScheduleText(raw);
      if (!mounted) return;
      setState(() => _busyAi = false);
      await _confirmImportCourses(parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAi = false);
      showAiError(
        context,
        e,
        onOpenSettings: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      );
    }
  }

  Future<void> _confirmImportCourses(List<Course> parsed) async {
    final l = context.l10n;
    final selected = List<bool>.filled(parsed.length, true);
    var replaceAll = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.scheduleConfirmImportTitle(parsed.length),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.scheduleReplaceAllSwitch),
                value: replaceAll,
                onChanged: (v) => setS(() => replaceAll = v),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: parsed.length,
                  itemBuilder: (_, i) {
                    final c = parsed[i];
                    final sub = l.scheduleCourseImportSub(
                      L10nHelper.weekdayLabel(ctx, c.weekday),
                      c.startSection,
                      c.endSection,
                      c.startWeek,
                      c.endWeek,
                      L10nHelper.weekTypeLabel(ctx, c.weekType),
                    );
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected[i],
                      onChanged: (v) => setS(() => selected[i] = v ?? true),
                      title: Text('${c.name}${c.location?.isNotEmpty == true ? ' @${c.location}' : ''}'),
                      subtitle: Text('$sub${c.teacher?.isNotEmpty == true ? ' · ${c.teacher}' : ''}'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.download_done),
                label: Text(l.scheduleConfirmImportBtn),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      final toSave = <Course>[
        for (var i = 0; i < parsed.length; i++)
          if (selected[i]) parsed[i],
      ];
      await Repo.importCourses(toSave, replaceAll: replaceAll);
      if (!mounted) return;
      toast(context, l.scheduleImportedToast(toSave.length));
      _load();
    }
  }

  Future<void> _openSettings() async {
    var start = _semesterStart;
    var sections = _sections;
    var remEnabled = await ReminderService.isEnabled();
    var remMins = await ReminderService.minutesBefore();
    var useSysClock = await ReminderService.useSystemClock();
    var notifStatus = await ReminderService.checkNotificationStatus();
    if (!mounted) return;
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(child: Text(l.scheduleSettingsTitle)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!notifStatus.enabled || notifStatus.importance < 4 || !notifStatus.vibrate)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l.scheduleColorOsWarnTitle,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.scheduleColorOsWarnSub,
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ReminderService.openNotificationSettings();
                            final s = await ReminderService.checkNotificationStatus();
                            setD(() => notifStatus = s);
                          },
                          icon: const Icon(Icons.settings_suggest_rounded, size: 16),
                          label: Text(l.scheduleOpenChannelSettingsBtn, style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.scheduleEnableReminderSwitch),
                  subtitle: Text(l.scheduleEnableReminderSub),
                  value: remEnabled,
                  onChanged: (v) => setD(() => remEnabled = v),
                ),
                if (remEnabled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.busRemindBeforeLabel),
                    trailing: DropdownButton<int>(
                      value: remMins,
                      items: [
                        for (final m in [5, 10, 15, 30])
                          DropdownMenuItem(value: m, child: Text(l.busRemindMinsOption(m))),
                      ],
                      onChanged: (v) => setD(() => remMins = v ?? remMins),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationDiagnosticsScreen()),
                        );
                      },
                      icon: const Icon(Icons.health_and_safety_rounded, size: 16),
                      label: Text(l.scheduleDiagnoseBtn, style: const TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ReminderService.openAppNotificationSettings(),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(l.scheduleSysNotifBtn, style: const TextStyle(fontSize: 12)),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await ReminderService.testNotification();
                        if (ctx.mounted) toast(ctx, l.scheduleTestVibToast);
                      },
                      icon: const Icon(Icons.vibration_rounded, size: 18),
                      label: Text(l.scheduleTestVibBtn, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(height: 22),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.scheduleUseSysClockSwitch),
                  subtitle: Text(l.scheduleUseSysClockSub),
                  value: useSysClock,
                  onChanged: (v) => setD(() => useSysClock = v),
                ),
                if (useSysClock)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        await ReminderService.setMinutesBefore(remMins);
                        final info = await ReminderService.setNextCourseInSystemClock();
                        if (!ctx.mounted) return;
                        if (info != null) {
                          toast(ctx, l.scheduleWriteNextAlarmToast(info));
                        } else {
                          toast(ctx, l.scheduleNoUpcomingClassToast);
                        }
                      },
                      icon: const Icon(Icons.alarm_add_rounded, size: 18),
                      label: Text(l.scheduleWriteNextAlarmBtn),
                    ),
                  ),
                const Divider(height: 22),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.scheduleFirstWeekMonLabel),
                  subtitle: Text(fmtDate(start)),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: l.schedulePickSemesterStartHelp,
                    );
                    if (d != null) setD(() => start = mondayOf(d));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.scheduleSectionsPerDayLabel),
                  trailing: DropdownButton<int>(
                    value: sections,
                    items: [for (var i = 4; i <= 16; i++) DropdownMenuItem(value: i, child: Text(l.scheduleSectionsCount(i)))],
                    onChanged: (v) => setD(() => sections = v ?? sections),
                  ),
                ),
                const Divider(height: 22),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger(ctx),
                    side: BorderSide(color: AppColors.softBorder(ctx, AppColors.danger(ctx))),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx, false);
                    _confirmClearAllCourses();
                  },
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: Text(l.scheduleClearAllTitle),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.commonSave)),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ReminderService.requestPermission();
      await ReminderService.setEnabled(remEnabled);
      await ReminderService.setMinutesBefore(remMins);
      await ReminderService.setUseSystemClock(useSysClock);
      if (dateOnly(start) != dateOnly(_semesterStart)) {
        await AcademicCalendarService.saveManualConfig(
          ManualSemesterConfig(
            name: _activeTerm.localizedName(isEn: context.isEnLocale),
            week1Start: start,
            totalWeeks: _activeTerm.totalWeeks,
            selectedTermId: _activeTerm.id,
          ),
        );
      }
      await Repo.setSectionsPerDay(sections);
      _load(resetWeek: true);
    }
  }

  String _shortMd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _weekHeadingText(BuildContext context, WeekStatusInfo info) {
    final l = context.l10n;
    if (info.isBeforeSemester) return l.scheduleBeforeSemesterTitle;
    if (info.isAfterTeaching) return l.scheduleAfterSemesterTitle(info.week);
    return l.scheduleWeekTitle(info.week);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final weekInfo = _activeTerm.evaluateWeek(_week);
    final weekTitle = _weekHeadingText(context, weekInfo);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _openSemesterSettings,
          child: Column(
            children: [
              Text(
                weekTitle,
                key: const ValueKey('schedule_appbar_week_title'),
                style: AppTypography.sectionTitle(context),
              ),
              Text(
                _activeTerm.localizedName(isEn: context.isEnLocale),
                style: AppTypography.caption(context),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: l.busBoardTitle,
            icon: const Icon(Icons.directions_bus_rounded),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BusScheduleScreen()));
            },
          ),
          IconButton(
            tooltip: l.scheduleImportTitle,
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _openImportMenu,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) {
              if (v == 'semester') {
                _openSemesterSettings();
              } else if (v == 'settings') {
                _openSettings();
              } else if (v == 'clear') {
                _confirmClearAllCourses();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'semester',
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Text(l.scheduleSemesterSettingsAction),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Text(l.scheduleSettingsTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded, size: 18, color: AppColors.danger(ctx)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      l.scheduleClearAllTitle,
                      style: TextStyle(color: AppColors.danger(ctx)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        tooltip: l.scheduleAddCourseTooltip,
        child: const Icon(Icons.add),
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                _weekNavBar(weekInfo),
                const Divider(height: 1),
                if (_weather != null && _weather!.isRainy)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.xs + 2,
                    ),
                    color: AppColors.softBg(
                      context,
                      AppColors.info(context),
                      lightAlpha: 0.14,
                      darkAlpha: 0.20,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.umbrella_rounded, size: 16, color: AppColors.primary(context)),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Expanded(
                          child: Text(
                            l.scheduleRainBanner(fmtNum(_weather!.precipProb)),
                            style: AppTypography.badge(context, color: AppColors.textPrimary(context))
                                .copyWith(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    key: const ValueKey('schedule_week_pageview'),
                    controller: _pageCtrl,
                    itemCount: _pageCount,
                    onPageChanged: (pageIndex) {
                      final newWeek = _pageToWeek(pageIndex);
                      if (newWeek != _week) {
                        setState(() => _week = newWeek);
                        _loadWeekMarkers(newWeek, prefetchNeighbors: true);
                      }
                    },
                    itemBuilder: (context, pageIndex) {
                      final pageWeek = _pageToWeek(pageIndex);
                      return _weekPage(pageWeek);
                    },
                  ),
                ),
                if (_courses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text(l.scheduleManualAddBtn),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _openImportMenu,
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: Text(l.scheduleEmptyImportBtn),
                        ),
                      ],
                    ),
                  ),
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
                        Text(l.scheduleAiParsing),
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

  /// 顶部周数导航条：← 第 X 周 (MM-dd ~ MM-dd) [今天] →
  Widget _weekNavBar(WeekStatusInfo info) {
    final l = context.l10n;
    final scheduleColor = AppColors.moduleSchedule(context);
    final isCurrent = _week == _currentWeek;
    final rangeStr = l.scheduleWeekDateRange(
      _shortMd(info.startDate),
      _shortMd(info.endDate),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      color: AppColors.surface(context),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('schedule_prev_week_btn'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _week > _minWeek ? () => _animateToWeek(_week - 1) : null,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    rangeStr,
                    key: const ValueKey('schedule_week_date_range'),
                    style: AppTypography.body(context).copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ScaleTap(
                  onTap: () => _animateToWeek(_currentWeek),
                  child: Container(
                    key: const ValueKey('schedule_today_btn'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm + 2,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.surfaceSubtle(context)
                          : AppColors.softBg(
                              context,
                              scheduleColor,
                              lightAlpha: 0.16,
                              darkAlpha: 0.26,
                            ),
                      borderRadius: AppRadius.bPill,
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.border(context)
                            : AppColors.softBorder(context, scheduleColor),
                      ),
                    ),
                    child: Text(
                      l.scheduleTodayBtn,
                      style: AppTypography.badge(
                        context,
                        color: isCurrent ? AppColors.textSecondary(context) : scheduleColor,
                      ).copyWith(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('schedule_next_week_btn'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _week < _maxWeek ? () => _animateToWeek(_week + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _weekPage(int pageWeek) {
    final l = context.l10n;
    final info = _activeTerm.evaluateWeek(pageWeek);
    final weekHolidays = _holidaysByWeek[pageWeek] ?? const <String, HolidayInfo>{};
    final weekNonTeaching = _nonTeachingByWeek[pageWeek] ?? const <String, CalendarHolidayEntry>{};

    return Column(
      children: [
        if (info.isBeforeSemester)
          _periodBoundaryBanner(
            icon: Icons.hourglass_empty_rounded,
            color: AppColors.info(context),
            text: info.periodStatus == WeekPeriodStatus.orientation
                ? l.scheduleOrientationBanner
                : l.scheduleBeforeSemesterBanner(fmtDate(_activeTerm.week1Start)),
          ),
        if (info.isAfterTeaching)
          _periodBoundaryBanner(
            icon: Icons.assignment_turned_in_rounded,
            color: AppColors.accent(context),
            text: (_activeTerm.assessmentStart != null && _activeTerm.assessmentEnd != null)
                ? l.scheduleAssessmentBanner(
                    '${_shortMd(_activeTerm.assessmentStart!)} ~ ${_shortMd(_activeTerm.assessmentEnd!)}',
                  )
                : l.scheduleAfterSemesterBanner,
          ),
        if (weekHolidays.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs + 2,
            ),
            color: AppColors.softBg(
              context,
              AppColors.warning(context),
              lightAlpha: 0.14,
              darkAlpha: 0.22,
            ),
            child: Row(
              children: [
                Icon(Icons.celebration_rounded, size: 16, color: AppColors.warning(context)),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    l.holidayWeekBanner(
                      weekHolidays.entries
                          .map((e) => '${e.key.substring(5)} ${e.value.localizedName(isEn: context.isEnLocale)}')
                          .join(' · '),
                    ),
                    style: AppTypography.badge(context, color: AppColors.textPrimary(context))
                        .copyWith(fontSize: 11.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (weekNonTeaching.isNotEmpty)
          InkWell(
            onTap: _openSemesterSettings,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs + 2,
              ),
              color: AppColors.surfaceSubtle(context),
              child: Row(
                children: [
                  Icon(
                    Icons.event_note_rounded,
                    size: 15,
                    color: AppColors.textSecondary(context),
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      l.scheduleNonTeachingBanner(
                        weekNonTeaching.keys.map((k) => k.substring(5)).join(' · '),
                      ),
                      style: AppTypography.caption(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: AppColors.textTertiary(context),
                  ),
                ],
              ),
            ),
          ),
        _header(pageWeek, weekHolidays, weekNonTeaching),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: _grid(pageWeek, weekHolidays, weekNonTeaching),
          ),
        ),
      ],
    );
  }

  Widget _periodBoundaryBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs + 2,
      ),
      color: AppColors.softBg(context, color, lightAlpha: 0.12, darkAlpha: 0.22),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Text(
              text,
              style: AppTypography.badge(context, color: color).copyWith(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(
    int pageWeek,
    Map<String, HolidayInfo> weekHolidays,
    Map<String, CalendarHolidayEntry> weekNonTeaching,
  ) {
    final l = context.l10n;
    final monday = _activeTerm.weekStartDate(pageWeek);
    final todayD = dateOnly(_now);
    final cs = Theme.of(context).colorScheme;
    final primary = AppColors.primary(context);
    final warning = AppColors.warning(context);

    return SizedBox(
      height: 50,
      child: Row(
        children: [
          SizedBox(
            width: _leftWidth,
            child: Center(
              child: Text(
                l.scheduleMonthHeader(monday.month),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Builder(builder: (_) {
              final d = monday.add(Duration(days: i));
              final dKey = fmtDate(d);
              final isToday = d == todayD;
              final isTodayWeekdayInOtherWeek = !isToday && d.weekday == todayD.weekday;
              final holiday = weekHolidays[dKey];
              final nonTeaching = holiday == null ? weekNonTeaching[dKey] : null;

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: holiday != null
                        ? AppColors.softBg(context, warning, lightAlpha: 0.20, darkAlpha: 0.28)
                        : nonTeaching != null
                            ? AppColors.surfaceSubtle(context)
                            : (isToday ? cs.primaryContainer : null),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        L10nHelper.weekdayLabel(context, i + 1),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: (isToday || holiday != null) ? FontWeight.bold : null,
                          color: holiday != null ? warning : null,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${d.day}', style: const TextStyle(fontSize: 10)),
                          if (holiday != null) ...[
                            const SizedBox(width: 2),
                            Text(
                              l.holidayShortBadge,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: warning,
                              ),
                            ),
                          ] else if (nonTeaching != null) ...[
                            const SizedBox(width: 2),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: AppColors.textTertiary(context),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (isToday || isTodayWeekdayInOtherWeek)
                        Container(
                          key: ValueKey('today_dot_w${pageWeek}_d${d.weekday}'),
                          margin: const EdgeInsets.only(top: 2),
                          width: 4.5,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: isToday ? primary : primary.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _grid(
    int pageWeek,
    Map<String, HolidayInfo> weekHolidays,
    Map<String, CalendarHolidayEntry> weekNonTeaching,
  ) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final warning = AppColors.warning(context);
    final monday = _activeTerm.weekStartDate(pageWeek);
    final info = _activeTerm.evaluateWeek(pageWeek);

    return LayoutBuilder(builder: (context, constraints) {
      final colWidth = (constraints.maxWidth - _leftWidth) / 7;
      final height = _sections * _cellHeight;
      final visible = info.periodStatus == WeekPeriodStatus.teaching
          ? _courses.where((c) => c.activeInWeek(pageWeek)).toList()
          : const <Course>[];

      return SizedBox(
        height: height,
        child: Stack(
          children: [
            for (var s = 0; s < _sections; s++)
              Positioned(
                left: 0,
                top: s * _cellHeight,
                width: _leftWidth,
                height: _cellHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${s + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(
                      '${ReminderService.sectionStartTime(s + 1).hour.toString().padLeft(2, '0')}:${ReminderService.sectionStartTime(s + 1).minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: cs.outline, fontSize: 8.5),
                    ),
                  ],
                ),
              ),
            for (var d = 0; d < 7; d++)
              for (var s = 0; s < _sections; s++)
                Positioned(
                  left: _leftWidth + d * colWidth,
                  top: s * _cellHeight,
                  width: colWidth,
                  height: _cellHeight,
                  child: InkWell(
                    onTap: () => _edit(weekday: d + 1, section: s + 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: weekHolidays.containsKey(fmtDate(monday.add(Duration(days: d))))
                            ? AppColors.softBg(context, warning, lightAlpha: 0.08, darkAlpha: 0.12)
                            : weekNonTeaching.containsKey(fmtDate(monday.add(Duration(days: d))))
                                ? AppColors.surfaceSubtle(context).withValues(alpha: 0.55)
                                : null,
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5),
                      ),
                    ),
                  ),
                ),
            for (final c in visible)
              if (!weekHolidays.containsKey(fmtDate(monday.add(Duration(days: c.weekday - 1)))))
                Positioned(
                  left: _leftWidth + (c.weekday - 1) * colWidth + 1.5,
                  top: (c.startSection - 1) * _cellHeight + 1.5,
                  width: colWidth - 3,
                  height: (c.endSection - c.startSection + 1) * _cellHeight - 3,
                  child: Material(
                    color: Color(c.color),
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _showCourse(c),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Text(
                          '${c.name}${c.location?.isNotEmpty == true ? '\n@${c.location}' : ''}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.2),
                          overflow: TextOverflow.fade,
                        ),
                      ),
                    ),
                  ),
                ),
            for (var d = 0; d < 7; d++)
              if (weekHolidays.containsKey(fmtDate(monday.add(Duration(days: d)))))
                Positioned(
                  left: _leftWidth + d * colWidth + 2,
                  top: 4,
                  width: colWidth - 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.softBg(context, warning, lightAlpha: 0.88, darkAlpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${weekHolidays[fmtDate(monday.add(Duration(days: d)))]!.localizedName(isEn: context.isEnLocale)}\n${l.holidayColumnLabel}',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                )
              else if (weekNonTeaching.containsKey(fmtDate(monday.add(Duration(days: d)))))
                Positioned(
                  left: _leftWidth + d * colWidth + 2,
                  top: 4,
                  width: colWidth - 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle(context),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.border(context)),
                      ),
                      child: Text(
                        l.scheduleNonTeachingLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary(context),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      );
    });
  }

  void _showCourse(Course c) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              _info(
                Icons.schedule,
                l.scheduleCourseDetailSection(
                  L10nHelper.weekdayLabel(ctx, c.weekday),
                  ReminderService.formatRange(c.startSection, c.endSection),
                  c.startSection,
                  c.endSection,
                ),
              ),
              _info(
                Icons.date_range,
                l.scheduleCourseDetailWeeks(
                  c.startWeek,
                  c.endWeek,
                  L10nHelper.weekTypeLabel(ctx, c.weekType),
                ),
              ),
              if (c.location?.isNotEmpty == true) _info(Icons.place_outlined, c.location!),
              if (c.teacher?.isNotEmpty == true) _info(Icons.person_outline, c.teacher!),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      if (await confirm(context, l.scheduleDeleteCourseConfirm(c.name))) {
                        await Repo.deleteCourse(c.id!);
                        _load();
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.commonDelete),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _edit(course: c);
                    },
                    icon: const Icon(Icons.edit),
                    label: Text(l.commonEdit),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 8), Expanded(child: Text(text))]),
      );
}
