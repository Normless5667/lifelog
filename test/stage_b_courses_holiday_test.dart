import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/screens/schedule/course_edit_screen.dart';
import 'package:lifelog/services/holiday_service.dart';

void main() {
  group('Stage B: HolidayService builtin + Nager.Date supplement + country inference', () {
    late Map<String, Map<String, HolidayInfo>> builtinMap;

    setUpAll(() async {
      final raw = File('assets/holidays.json').readAsStringSync();
      builtinMap = await HolidayService.loadBuiltinMap(overrideRawJson: raw);
    });

    test('assets/holidays.json covers VN/CN/GB/US including lunar Tet and Hung Kings in 2026', () {
      expect(builtinMap.keys, containsAll(['VN', 'CN', 'GB', 'US']));

      final vn = builtinMap['VN']!;
      // Nager.Date misses Tet and Hung Kings — verify our local asset has all of them!
      expect(vn['2026-01-01'], isNotNull);
      expect(vn['2026-02-17'], isNotNull); // Tet Day 1
      expect(vn['2026-02-17']!.nameZh, contains('春节'));
      expect(vn['2026-04-26'], isNotNull); // Hung Kings
      expect(vn['2026-04-26']!.nameZh, contains('雄王'));
      expect(vn['2026-04-30'], isNotNull);
      expect(vn['2026-05-01'], isNotNull);
      expect(vn['2026-09-02'], isNotNull);

      final cn = builtinMap['CN']!;
      expect(cn['2026-02-17'], isNotNull);
      expect(cn['2026-10-01'], isNotNull);

      expect(builtinMap['GB']!['2026-12-25'], isNotNull);
      expect(builtinMap['US']!['2026-07-04'], isNotNull);
    });

    test('mergeHolidayMaps supplements missing dates and NEVER overwrites builtin holidays', () {
      final vnBuiltin = builtinMap['VN']!;
      const nagerPayload = '''
      [
        {"date": "2026-01-01", "localName": "Remote Override Attempt", "name": "Remote New Year"},
        {"date": "2026-11-24", "localName": "Extra Local Holiday", "name": "Extra Holiday"}
      ]
      ''';
      final remote = HolidayService.parseNagerDateJson(nagerPayload, 'VN');
      final merged = HolidayService.mergeHolidayMaps(
        builtin: vnBuiltin,
        remoteSupplement: remote,
      );

      // Existing builtin 2026-01-01 MUST NOT be overwritten
      expect(merged['2026-01-01']!.fromBuiltin, isTrue);
      expect(merged['2026-01-01']!.nameZh, '元旦');

      // Missing date 2026-11-24 IS supplemented
      expect(merged['2026-11-24'], isNotNull);
      expect(merged['2026-11-24']!.fromBuiltin, isFalse);
      expect(merged['2026-11-24']!.nameEn, 'Extra Holiday');

      // Lunar Tet remains intact
      expect(merged['2026-02-17']!.fromBuiltin, isTrue);
    });

    test('inferCountryFromCityAndCoords maps cities & coordinates without extra permissions', () {
      expect(HolidayService.inferCountryFromCityAndCoords(city: 'Hanoi'), 'VN');
      expect(HolidayService.inferCountryFromCityAndCoords(city: '河内 / BUV (Hanoi)'), 'VN');
      expect(HolidayService.inferCountryFromCityAndCoords(city: 'Ho Chi Minh City'), 'VN');
      expect(HolidayService.inferCountryFromCityAndCoords(city: 'Shanghai'), 'CN');
      expect(HolidayService.inferCountryFromCityAndCoords(city: '北京 (Beijing)'), 'CN');
      expect(HolidayService.inferCountryFromCityAndCoords(city: 'London'), 'GB');
      expect(HolidayService.inferCountryFromCityAndCoords(city: 'New York'), 'US');

      // Coordinate fallback when city string is unknown
      expect(
        HolidayService.inferCountryFromCityAndCoords(city: 'Unknown', lat: 20.96, lon: 105.94),
        'VN',
      );
      expect(
        HolidayService.inferCountryFromCityAndCoords(city: 'Unknown', lat: 51.50, lon: -0.12),
        'GB',
      );
      expect(
        HolidayService.inferCountryFromCityAndCoords(city: 'Unknown', lat: 31.23, lon: 121.47),
        'CN',
      );
    });
  });

  group('Stage B: Course source tagging & Multi-weekday manual form', () {
    test('Course toMap/fromMap distinguishes builtin vs user source', () {
      final builtin = Course(
        name: 'Database Principles',
        weekday: 1,
        startSection: 1,
        endSection: 3,
        color: 0xFF26A69A,
        source: Course.sourceBuiltin,
      );
      expect(builtin.isBuiltin, isTrue);
      final restoredBuiltin = Course.fromMap(builtin.toMap());
      expect(restoredBuiltin.source, Course.sourceBuiltin);
      expect(restoredBuiltin.isBuiltin, isTrue);

      final userCourse = Course.fromMap({
        'name': 'Linear Algebra',
        'weekday': 3,
        'start_section': 1,
        'end_section': 2,
        'start_week': 1,
        'end_week': 16,
        'week_type': 0,
        'color': 0xFF42A5F5,
      });
      expect(userCourse.source, Course.sourceUser);
      expect(userCourse.isBuiltin, isFalse);
    });

    testWidgets('CourseEditScreen supports multi-weekday selection (Mon/Wed/Fri) in one save',
        (tester) async {
      List<Course>? savedCourses;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: CourseEditScreen(
            initialWeekday: 1,
            initialSection: 1,
            onSaveOverrideForTest: (list) async {
              savedCourses = list;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter course name
      await tester.enterText(find.byType(TextFormField).first, '高等数学');
      await tester.pump();

      // Select Wednesday and Friday in addition to Monday
      await tester.tap(find.text('周三'));
      await tester.pump();
      await tester.tap(find.text('周五'));
      await tester.pump();

      // Tap top-right save button
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(savedCourses, isNotNull);
      expect(savedCourses!.length, 3);
      expect(savedCourses!.map((c) => c.weekday).toList(), [1, 3, 5]);
      expect(savedCourses!.every((c) => c.name == '高等数学' && c.source == Course.sourceUser), isTrue);
    });
  });
}
