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

  const CourseEditScreen({
    super.key,
    this.course,
    this.initialWeekday,
    this.initialSection,
    this.sectionsPerDay = 12,
  });

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late int _weekday;
  late int _start;
  late int _end;
  late RangeValues _weeks;
  late int _weekType;
  late int _color;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _weekday = c?.weekday ?? widget.initialWeekday ?? DateTime.now().weekday;
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
    await Repo.saveCourse(Course(
      id: widget.course?.id,
      name: _name.text.trim(),
      teacher: _teacher.text.trim(),
      location: _location.text.trim(),
      weekday: _weekday,
      startSection: _start,
      endSection: _end,
      startWeek: _weeks.start.round(),
      endWeek: _weeks.end.round(),
      weekType: _weekType,
      color: _color,
    ));
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
                prefixIcon: const Icon(Icons.menu_book_rounded, color: Color(0xFF26A69A)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? l.courseEditNameRequired : null,
              autofocus: widget.course == null,
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _location,
                  decoration: InputDecoration(
                    labelText: l.courseEditLocationLabel,
                    prefixIcon: const Icon(Icons.location_on_rounded, color: Color(0xFFEF5350)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _teacher,
                  decoration: InputDecoration(
                    labelText: l.courseEditTeacherLabel,
                    prefixIcon: const Icon(Icons.person_rounded, color: Color(0xFF42A5F5)),
                  ),
                ),
              ),
            ]),
            SectionTitle(l.courseEditWeekdayTitle, icon: Icons.calendar_today_rounded, iconColor: const Color(0xFF42A5F5)),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 1; i <= 7; i++)
                  ChoiceChip(
                    avatar: Icon(Icons.event_rounded, size: 16, color: _weekday == i ? Color(_color) : null),
                    label: Text(L10nHelper.weekdayLabel(context, i)),
                    selected: _weekday == i,
                    onSelected: (_) => setState(() => _weekday = i),
                  ),
              ],
            ),
            SectionTitle(l.courseEditSectionTitle, icon: Icons.access_time_rounded, iconColor: const Color(0xFFFFA726)),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _start,
                  decoration: InputDecoration(
                    labelText: l.courseEditStartSection,
                    prefixIcon: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF26A69A)),
                  ),
                  items: sectionItems,
                  onChanged: (v) => setState(() {
                    _start = v ?? _start;
                    if (_end < _start) _end = _start;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('end-$_start-$_end'),
                  initialValue: _end,
                  decoration: InputDecoration(
                    labelText: l.courseEditEndSection,
                    prefixIcon: const Icon(Icons.stop_circle_outlined, color: Color(0xFFEF5350)),
                  ),
                  items: sectionItems,
                  onChanged: (v) => setState(() => _end = v ?? _end),
                ),
              ),
            ]),
            SectionTitle(l.courseEditWeeksTitle, icon: Icons.date_range_rounded, iconColor: const Color(0xFFAB47BC)),
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
            SectionTitle(l.courseEditColorTitle, icon: Icons.palette_rounded, iconColor: const Color(0xFFEC407A)),
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
