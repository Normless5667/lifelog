import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/screens/schedule/schedule_screen.dart';
import 'package:lifelog/screens/settings/semester_settings_screen.dart';
import 'package:lifelog/services/academic_calendar_service.dart';
import 'package:lifelog/services/holiday_service.dart';
import 'package:lifelog/utils/date_utils.dart';
import 'package:lifelog/widgets/common.dart';

void main() {
  late AcademicCalendar buvCalendar;
  late AcademicTerm autumn2026;

  setUpAll(() {
    final raw = File('assets/academic_calendar.json').readAsStringSync();
    buvCalendar = AcademicCalendar.fromJsonString(raw);
    autumn2026 = buvCalendar.terms.firstWhere((t) => t.id == 'autumn-2026');
  });

  group('v3.0.1 AcademicCalendarService: week numbering, boundaries & confidence split', () {
    test('verifies BUV 2026/2027 calendar dates, Week 8 on 2026-11-20, and term auto-resolution',
        () {
      expect(fmtDate(autumn2026.week1Start), '2026-09-28');
      expect(autumn2026.totalWeeks, 12);

      // 2026-11-20 必须精确算作第 8 周
      final nov20 = DateTime(2026, 11, 20);
      expect(buvCalendar.resolveTermForDate(nov20).id, 'autumn-2026');
      expect(autumn2026.weekOfDate(nov20), 8);
      expect(weekOfSemester(autumn2026.week1Start, nov20), 8);

      // 第 1 周：09-28 ~ 10-04
      expect(fmtDate(autumn2026.weekStartDate(1)), '2026-09-28');
      expect(fmtDate(autumn2026.weekEndDate(1)), '2026-10-04');

      // 第 9 周：11-23 ~ 11-29
      expect(fmtDate(autumn2026.weekStartDate(9)), '2026-11-23');
      expect(fmtDate(autumn2026.weekEndDate(9)), '2026-11-29');

      // 第 0 周（迎新周 Orientation Week）：2026-09-21 开始，属于学期未开始
      final ori = autumn2026.evaluateWeek(0);
      expect(ori.periodStatus, WeekPeriodStatus.orientation);
      expect(ori.isBeforeSemester, isTrue);
      expect(fmtDate(ori.startDate), '2026-09-21');

      // 第 -1 周：学期未开始
      final pre = autumn2026.evaluateWeek(-1);
      expect(pre.periodStatus, WeekPeriodStatus.beforeSemester);
      expect(pre.isBeforeSemester, isTrue);

      // 第 13 周（2026-12-21 ~ 12-27）：Assessment Period 考试周
      final exam = autumn2026.evaluateWeek(13);
      expect(exam.periodStatus, WeekPeriodStatus.assessment);
      expect(exam.isAfterTeaching, isTrue);

      // 春季学期自动匹配：2027-01-18 为第 1 周
      final feb10 = DateTime(2027, 2, 10);
      final spring = buvCalendar.resolveTermForDate(feb10);
      expect(spring.id, 'spring-2027');
      expect(fmtDate(spring.week1Start), '2027-01-18');
      expect(spring.weekOfDate(feb10), 4);
    });

    test('confidence=low (e.g. 2026-11-24) is neutral by default and supports manual overrides', () {
      final defaultSplit = AcademicCalendarService.classifyCalendarEntries(
        entries: buvCalendar.allHolidays,
        overrides: const {},
      );

      // high 置信度直接作为假期生效
      expect(defaultSplit.confirmedHolidays['2026-12-25'], isNotNull);
      expect(defaultSplit.confirmedHolidays['2026-12-28'], isNotNull);
      expect(defaultSplit.confirmedHolidays['2027-01-01'], isNotNull);

      // low 置信度（2026-11-24）默认不作为假期，而是进入中性非教学日
      expect(defaultSplit.confirmedHolidays['2026-11-24'], isNull);
      expect(defaultSplit.neutralNonTeachingDays['2026-11-24'], isNotNull);

      // 手动覆盖为假期
      final asHoliday = AcademicCalendarService.classifyCalendarEntries(
        entries: buvCalendar.allHolidays,
        overrides: const {'2026-11-24': LowConfidenceOverride.holiday},
      );
      expect(asHoliday.confirmedHolidays['2026-11-24'], isNotNull);
      expect(asHoliday.neutralNonTeachingDays['2026-11-24'], isNull);

      // 手动覆盖为正常上课
      final asNormal = AcademicCalendarService.classifyCalendarEntries(
        entries: buvCalendar.allHolidays,
        overrides: const {'2026-11-24': LowConfidenceOverride.normal},
      );
      expect(asNormal.confirmedHolidays['2026-11-24'], isNull);
      expect(asNormal.neutralNonTeachingDays['2026-11-24'], isNull);
    });
  });

  group('v3.0.1 ScheduleScreen: PageView swipe, boundaries, Today jump & holiday hiding', () {
    testWidgets('supports horizontal week swipe, date ranges, boundaries, Today jump & holiday rules',
        (tester) async {
      final courses = [
        Course(
          id: 1,
          name: 'Linear Algebra',
          weekday: 1, // Monday
          startSection: 1,
          endSection: 2,
          startWeek: 1,
          endWeek: 12,
          color: 0xFF4F46E5,
        ),
        Course(
          id: 2,
          name: 'Computer Networks',
          weekday: 2, // Tuesday (hits 2026-11-24 low-conf in Week 9)
          startSection: 3,
          endSection: 4,
          startWeek: 1,
          endWeek: 12,
          color: 0xFF0D9488,
        ),
        Course(
          id: 3,
          name: 'Algorithms',
          weekday: 3, // Wednesday
          startSection: 1,
          endSection: 2,
          startWeek: 1,
          endWeek: 12,
          color: 0xFFF59E0B,
        ),
      ];

      // 2026-11-16（第 8 周周一）设为已确认假期；2026-11-24（第 9 周周二）为 low-confidence 非教学日
      final confirmedHolidays = <String, HolidayInfo>{
        '2026-11-16': const HolidayInfo(
          date: '2026-11-16',
          nameZh: '测试假期',
          nameEn: 'Test Holiday',
          countryCode: 'VN',
        ),
      };
      final neutralNonTeaching = <String, CalendarHolidayEntry>{
        '2026-11-24': const CalendarHolidayEntry(
          date: '2026-11-24',
          name: 'Institutional holiday',
          nameZh: '校历标注',
          confidence: CalendarHolidayConfidence.low,
        ),
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: ScheduleScreen(
            nowForTest: DateTime(2026, 11, 20), // Friday -> Week 8
            initialTermForTest: autumn2026,
            initialCoursesForTest: courses,
            initialHolidaysForTest: confirmedHolidays,
            initialNonTeachingForTest: neutralNonTeaching,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1) 初始显示第 8 周（11-16 ~ 11-22）
      expect(find.text('第 8 周'), findsOneWidget);
      expect(find.text('11-16 ~ 11-22'), findsOneWidget);

      // 2) 假期当天（2026-11-16 周一）不显示课程 Linear Algebra，非假期周三 Algorithms 正常显示
      expect(find.textContaining('Linear Algebra'), findsNothing);
      expect(find.textContaining('Algorithms'), findsOneWidget);

      // 3) 向左滑动切到第 9 周 -> 顶部显示「第 9 周」且日期范围 11-23 ~ 11-29
      final pageViewFinder = find.byKey(const ValueKey('schedule_week_pageview'));
      await tester.fling(pageViewFinder, const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('第 9 周'), findsOneWidget);
      expect(find.text('11-23 ~ 11-29'), findsOneWidget);

      // 4) 滑到第 9 周时，今天所在星期五（weekday=5）仍有小圆点标记
      expect(find.byKey(const ValueKey('today_dot_w9_d5')), findsOneWidget);

      // 5) 2026-11-24 (confidence=low) 以「非教学日」中性展示，不写「假期」二字，且不隐藏周二课程
      expect(find.text('非教学日'), findsOneWidget);
      expect(find.textContaining('2026-11-24'), findsNothing);
      expect(find.textContaining('11-24'), findsOneWidget);
      expect(find.textContaining('Computer Networks'), findsOneWidget);

      // 6) 点「今天」一键跳回第 8 周
      await tester.tap(find.byKey(const ValueKey('schedule_today_btn')));
      await tester.pumpAndSettle();
      expect(find.text('第 8 周'), findsOneWidget);
      expect(find.text('11-16 ~ 11-22'), findsOneWidget);

      // 7) 连续点击上一周到第 1 周，验证日期 09-28 ~ 10-04
      final prevBtn = find.byKey(const ValueKey('schedule_prev_week_btn'));
      for (var i = 0; i < 7; i++) {
        await tester.tap(prevBtn);
        await tester.pumpAndSettle();
      }
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.text('09-28 ~ 10-04'), findsOneWidget);

      // 8) 再往前一页到第 0 周（第 1 周之前）-> 显示「学期未开始」
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();
      expect(find.text('学期未开始'), findsOneWidget);
      expect(find.textContaining('学期未开始'), findsWidgets);

      // 9) 点「今天」回到第 8 周，再往后 5 周到第 13 周 -> 显示「学期结束，进入考试周」
      await tester.tap(find.byKey(const ValueKey('schedule_today_btn')));
      await tester.pumpAndSettle();
      final nextBtn = find.byKey(const ValueKey('schedule_next_week_btn'));
      for (var i = 0; i < 5; i++) {
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('学期结束，进入考试周'), findsOneWidget);
    });
  });

  group('v3.0.1 SemesterSettingsScreen: manual form & validation', () {
    testWidgets('allows editing semester name and total weeks and saves ManualSemesterConfig',
        (tester) async {
      ManualSemesterConfig? saved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: SemesterSettingsScreen(
            initialTermForTest: autumn2026,
            initialCalendarForTest: buvCalendar,
            nowForTest: DateTime(2026, 11, 20),
            onSaveOverrideForTest: (cfg) async {
              saved = cfg;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始实时预览正确算出第 8 周
      expect(find.textContaining('今天是第 8 周'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('semester_name_field')), 'Custom Fall 2026');
      await tester.enterText(find.byKey(const ValueKey('semester_total_weeks_field')), '16');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('semester_save_btn')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.name, 'Custom Fall 2026');
      expect(saved!.totalWeeks, 16);
      expect(fmtDate(saved!.week1Start), '2026-09-28');
    });
  });
}
