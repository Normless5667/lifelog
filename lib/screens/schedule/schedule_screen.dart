import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/database.dart';
import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/reminder_service.dart';
import '../../services/weather_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../settings/notification_diagnostics_screen.dart';
import '../settings/settings_screen.dart';
import 'bus_schedule_screen.dart';
import 'course_edit_screen.dart';

/// 周视图课表（支持点击添加、截图 AI 识别导入、粘贴教务文本/JSON 导入）
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _cellHeight = 60.0;
  static const _leftWidth = 30.0;

  List<Course> _courses = [];
  DateTime _semesterStart = mondayOf(DateTime.now());
  int _sections = 12;
  int _currentWeek = 1;
  int _week = 1;
  bool _loading = true;
  bool _busyAi = false;
  WeatherInfo? _weather;

  @override
  void initState() {
    super.initState();
    _load(resetWeek: true);
  }

  Future<void> _load({bool resetWeek = false}) async {
    final courses = await Repo.getCourses();
    final start = await Repo.getSemesterStart();
    final sections = await Repo.getSectionsPerDay();
    final weather = await WeatherService.getWeather();
    if (!mounted) return;
    setState(() {
      _courses = courses;
      _semesterStart = start;
      _sections = sections;
      _weather = weather;
      _currentWeek = weekOfSemester(start, DateTime.now()).clamp(1, 30);
      if (resetWeek) _week = _currentWeek;
      _loading = false;
    });
    ReminderService.syncAlarms();
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'preset') {
      final preset = AppDatabase.defaultScheduleCourses.map(Course.fromMap).toList();
      await _confirmImportCourses(preset);
    } else if (action == 'gallery') {
      await _importFromImage(ImageSource.gallery);
    } else if (action == 'camera') {
      await _importFromImage(ImageSource.camera);
    } else if (action == 'text') {
      await _importFromText();
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
      await Repo.setSemesterStart(start);
      await Repo.setSectionsPerDay(sections);
      _load(resetWeek: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _week > 1 ? () => setState(() => _week--) : null,
            ),
            GestureDetector(
              onTap: () => setState(() => _week = _currentWeek),
              child: Column(
                children: [
                  Text(l.scheduleWeekTitle(_week)),
                  Text(
                    _week == _currentWeek ? l.scheduleCurrentWeek : l.scheduleBackToCurrent,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _week < 30 ? () => setState(() => _week++) : null,
            ),
          ],
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
          IconButton(tooltip: l.scheduleImportTitle, icon: const Icon(Icons.file_upload_outlined), onPressed: _openImportMenu),
          IconButton(tooltip: l.scheduleSettingsTitle, icon: const Icon(Icons.tune), onPressed: _openSettings),
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
                if (_weather != null && _weather!.isRainy)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    color: const Color(0xFF42A5F5).withValues(alpha: 0.16),
                    child: Row(
                      children: [
                        const Icon(Icons.umbrella_rounded, size: 16, color: Color(0xFF2B5B84)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l.scheduleRainBanner(fmtNum(_weather!.precipProb)),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                _header(),
                const Divider(height: 1),
                Expanded(child: SingleChildScrollView(child: _grid())),
                if (_courses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(l.scheduleEmptyTapHint),
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

  Widget _header() {
    final l = context.l10n;
    final monday = mondayOf(_semesterStart).add(Duration(days: (_week - 1) * 7));
    final todayD = dateOnly(DateTime.now());
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
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
              final isToday = d == todayD;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isToday ? cs.primaryContainer : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        L10nHelper.weekdayLabel(context, i + 1),
                        style: TextStyle(fontSize: 12, fontWeight: isToday ? FontWeight.bold : null),
                      ),
                      Text('${d.day}', style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _grid() {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final colWidth = (constraints.maxWidth - _leftWidth) / 7;
      final height = _sections * _cellHeight;
      final visible = _courses.where((c) => c.activeInWeek(_week)).toList();
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
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5),
                      ),
                    ),
                  ),
                ),
            for (final c in visible)
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
