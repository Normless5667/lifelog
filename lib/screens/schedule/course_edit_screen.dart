import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

const courseColors = <int>[
  0xFF26A69A, 0xFF42A5F5, 0xFFAB47BC, 0xFFEF5350, 0xFFFFA726,
  0xFF66BB6A, 0xFF5C6BC0, 0xFFEC407A, 0xFF8D6E63, 0xFF29B6F6,
];

class CourseEditScreen extends StatefulWidget {
  final Course? course;
  final int? initialWeekday;
  final int? initialSection;
  final int sectionsPerDay;

  @visibleForTesting
  final Future<void> Function(List<Course> courses)? onSaveOverrideForTest;

  const CourseEditScreen({
    super.key,
    this.course,
    this.initialWeekday,
    this.initialSection,
    this.sectionsPerDay = 12,
    this.onSaveOverrideForTest,
  });

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final Set<int> _selectedWeekdays;
  late int _start;
  late int _end;
  late RangeValues _weeks;
  late int _weekType;
  late int _color;

  bool get _isCreateMode => widget.course == null;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _selectedWeekdays = {c?.weekday ?? widget.initialWeekday ?? DateTime.now().weekday};
    _start = c?.startSection ?? widget.initialSection ?? 1;
    _end = c?.endSection ?? (_start + 1).clamp(1, widget.sectionsPerDay);
    _weeks = RangeValues((c?.startWeek ?? 1).toDouble(), (c?.endWeek ?? 16).toDouble());
    _weekType = c?.weekType ?? 0;
    _color = c?.color ?? courseColors[DateTime.now().millisecond % courseColors.length];
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_end < _start) {
      toast(context, context.l10n.courseEditSectionOrderError);
      return;
    }
    final days = _selectedWeekdays.toList()..sort();
    if (days.isEmpty) return;

    final toSave = days
        .map(
          (wd) => Course(
            id: _isCreateMode ? null : widget.course?.id,
            name: _name.text.trim(),
            teacher: _teacher.text.trim(),
            location: _location.text.trim(),
            weekday: wd,
            startSection: _start,
            endSection: _end,
            startWeek: _weeks.start.round(),
            endWeek: _weeks.end.round(),
            weekType: _weekType,
            color: _color,
            source: Course.sourceUser,
          ),
        )
        .toList();

    if (widget.onSaveOverrideForTest != null) {
      await widget.onSaveOverrideForTest!(toSave);
    } else if (_isCreateMode && toSave.length > 1) {
      await Repo.saveCourses(toSave);
      if (mounted) toast(context, context.l10n.courseEditAddedMultiToast(toSave.length));
    } else {
      await Repo.saveCourse(toSave.first);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final maxSection = widget.sectionsPerDay < _end ? _end : widget.sectionsPerDay;
    final sectionItems = [
      for (var i = 1; i <= maxSection; i++)
        DropdownMenuItem(
          value: i,
          child: Text(
            l.courseEditSectionItem(
              i,
              '${ReminderService.sectionStartTime(i).hour.toString().padLeft(2, '0')}:${ReminderService.sectionStartTime(i).minute.toString().padLeft(2, '0')}',
            ),
          ),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Color(_color).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.school_rounded, color: Color(_color), size: 20),
            ),
            const SizedBox(width: 10),
            Text(widget.course == null ? l.courseEditAddTitle : l.courseEditUpdateTitle),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(l.commonSave),
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l.courseEditNameLabel,
                prefixIcon: Icon(Icons.menu_book_rounded, color: AppColors.teal(context)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? l.courseEditNameRequired : null,
              autofocus: widget.course == null,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _location,
                  decoration: InputDecoration(
                    labelText: l.courseEditLocationLabel,
                    prefixIcon: Icon(Icons.location_on_rounded, color: AppColors.moduleWorkout(context)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  controller: _teacher,
                  decoration: InputDecoration(
                    labelText: l.courseEditTeacherLabel,
                    prefixIcon: Icon(Icons.person_rounded, color: AppColors.moduleSchedule(context)),
                  ),
                ),
              ),
            ]),
            SectionTitle(l.courseEditWeekdayTitle, icon: Icons.calendar_today_rounded, iconColor: AppColors.moduleSchedule(context)),
            if (_isCreateMode)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(l.courseEditMultiWeekdayHint, style: AppTypography.caption(context)),
              ),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 1; i <= 7; i++)
                  _isCreateMode
                      ? FilterChip(
                          avatar: Icon(
                            Icons.event_rounded,
                            size: 16,
                            color: _selectedWeekdays.contains(i) ? Color(_color) : null,
                          ),
                          label: Text(L10nHelper.weekdayLabel(context, i)),
                          selected: _selectedWeekdays.contains(i),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _selectedWeekdays.add(i);
                            } else if (_selectedWeekdays.length > 1) {
                              _selectedWeekdays.remove(i);
                            }
                          }),
                        )
                      : ChoiceChip(
                          avatar: Icon(
                            Icons.event_rounded,
                            size: 16,
                            color: _selectedWeekdays.contains(i) ? Color(_color) : null,
                          ),
                          label: Text(L10nHelper.weekdayLabel(context, i)),
                          selected: _selectedWeekdays.contains(i),
                          onSelected: (_) => setState(() {
                            _selectedWeekdays
                              ..clear()
                              ..add(i);
                          }),
                        ),
              ],
            ),
            SectionTitle(l.courseEditSectionTitle, icon: Icons.access_time_rounded, iconColor: AppColors.warning(context)),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _start,
                  decoration: InputDecoration(
                    labelText: l.courseEditStartSection,
                    prefixIcon: Icon(Icons.play_circle_outline_rounded, color: AppColors.teal(context)),
                  ),
                  items: sectionItems,
                  onChanged: (v) => setState(() {
                    _start = v ?? _start;
                    if (_end < _start) _end = _start;
                  }),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('end-$_start-$_end'),
                  initialValue: _end,
                  decoration: InputDecoration(
                    labelText: l.courseEditEndSection,
                    prefixIcon: Icon(Icons.stop_circle_outlined, color: AppColors.danger(context)),
                  ),
                  items: sectionItems,
                  onChanged: (v) => setState(() => _end = v ?? _end),
                ),
              ),
            ]),
            SectionTitle(l.courseEditWeeksTitle, icon: Icons.date_range_rounded, iconColor: AppColors.moduleAi(context)),
            Text(
              l.courseEditWeeksSummary(
                _weeks.start.round(),
                _weeks.end.round(),
                ReminderService.formatRange(_start, _end),
              ),
            ),
            RangeSlider(
              values: _weeks,
              min: 1,
              max: 30,
              divisions: 29,
              labels: RangeLabels('${_weeks.start.round()}', '${_weeks.end.round()}'),
              onChanged: (v) => setState(() => _weeks = v),
            ),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, icon: const Icon(Icons.repeat_rounded), label: Text(l.scheduleWeekEvery)),
                ButtonSegment(value: 1, icon: const Icon(Icons.looks_one_rounded), label: Text(l.scheduleWeekOdd)),
                ButtonSegment(value: 2, icon: const Icon(Icons.looks_two_rounded), label: Text(l.scheduleWeekEven)),
              ],
              selected: {_weekType},
              onSelectionChanged: (s) => setState(() => _weekType = s.first),
            ),
            SectionTitle(l.courseEditColorTitle, icon: Icons.palette_rounded, iconColor: AppColors.accent(context)),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in courseColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(c),
                      child: _color == c ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(l.courseEditSaveBtn),
            ),
          ],
        ),
      ),
    );
  }
}
