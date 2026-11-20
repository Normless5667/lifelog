import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations_en.dart';
import 'package:lifelog/l10n/app_localizations_zh.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/utils/course_status.dart';
import 'package:lifelog/widgets/common.dart';
import 'package:lifelog/widgets/m3_sliding_nav_bar.dart';

Course _makeCourse(String name, int startSection, int endSection) {
  return Course(
    name: name,
    weekday: 1,
    startSection: startSection,
    endSection: endSection,
    startWeek: 1,
    endWeek: 16,
    color: 0xFF4F46E5,
  );
}

void main() {
  group('Stage C §2.3: Course 3-state status & countdown', () {
    // 第 1-2 节: 09:00-10:00, 第 5-6 节: 11:00-12:00
    final morningCourse = _makeCourse('Linear Algebra', 1, 2);
    final noonCourse = _makeCourse('Computer Networks', 5, 6);

    test('evaluates upcoming, inProgress, and completed accurately', () {
      final beforeFirst = DateTime(2026, 4, 20, 8, 30);
      final s1 = summarizeTodayCourses([noonCourse, morningCourse], beforeFirst);
      expect(s1.items.first.course.name, 'Linear Algebra');
      expect(s1.items[0].status, CourseStatus.upcoming);
      expect(s1.items[0].minutesUntilStart, 30);
      expect(s1.items[1].status, CourseStatus.upcoming);
      expect(s1.items[1].minutesUntilStart, 150);
      expect(s1.current, isNull);
      expect(s1.next?.course.name, 'Linear Algebra');
      expect(s1.allDone, isFalse);

      final duringFirst = DateTime(2026, 4, 20, 9, 20);
      final s2 = summarizeTodayCourses([morningCourse, noonCourse], duringFirst);
      expect(s2.items[0].status, CourseStatus.inProgress);
      expect(s2.items[0].minutesUntilEnd, 40);
      expect(s2.items[1].status, CourseStatus.upcoming);
      expect(s2.items[1].minutesUntilStart, 100);
      expect(s2.current?.course.name, 'Linear Algebra');
      expect(s2.next?.course.name, 'Computer Networks');
      expect(s2.allDone, isFalse);

      // 最后 30 秒向上取整为 1 分钟，不显示 0 分钟
      final lastHalfMin = DateTime(2026, 4, 20, 9, 59, 30);
      final infoLast = evaluateCourseStatus(morningCourse, lastHalfMin);
      expect(infoLast.status, CourseStatus.inProgress);
      expect(infoLast.minutesUntilEnd, 1);

      // 恰好到下课整点 -> 已上完
      final exactEnd = DateTime(2026, 4, 20, 10, 0, 0);
      final s3 = summarizeTodayCourses([morningCourse, noonCourse], exactEnd);
      expect(s3.items[0].status, CourseStatus.completed);
      expect(s3.items[1].status, CourseStatus.upcoming);
      expect(s3.items[1].minutesUntilStart, 60);
      expect(s3.completedCount, 1);
      expect(s3.current, isNull);
      expect(s3.next?.course.name, 'Computer Networks');
      expect(s3.allDone, isFalse);

      // 全部课程结束 -> allDone = true
      final afterAll = DateTime(2026, 4, 20, 12, 5);
      final s4 = summarizeTodayCourses([morningCourse, noonCourse], afterAll);
      expect(s4.completedCount, 2);
      expect(s4.current, isNull);
      expect(s4.next, isNull);
      expect(s4.allDone, isTrue);
    });

    test('formats localized countdown strings in ZH and EN', () {
      final zh = AppLocalizationsZh();
      final en = AppLocalizationsEn();

      final upcomingShort = evaluateCourseStatus(morningCourse, DateTime(2026, 4, 20, 8, 45));
      expect(formatCourseStatusLabel(zh, upcomingShort), '15 分钟后开始');
      expect(formatCourseStatusLabel(en, upcomingShort), 'In 15m');

      final upcomingLong = evaluateCourseStatus(noonCourse, DateTime(2026, 4, 20, 9, 20));
      expect(formatCourseStatusLabel(zh, upcomingLong), '1 小时 40 分后开始');
      expect(formatCourseStatusLabel(en, upcomingLong), 'In 1h 40m');

      final inProgress = evaluateCourseStatus(morningCourse, DateTime(2026, 4, 20, 9, 35));
      expect(formatCourseStatusLabel(zh, inProgress), '还有 25 分钟下课');
      expect(formatCourseStatusLabel(en, inProgress), '25m left');

      final done = evaluateCourseStatus(morningCourse, DateTime(2026, 4, 20, 10, 5));
      expect(formatCourseStatusLabel(zh, done), '已上完');
      expect(formatCourseStatusLabel(en, done), 'Done');
    });
  });

  group('Stage C §2.4: Material 3 motion & reduced-motion support', () {
    testWidgets('ScaleTap uses 0.98 / 120ms / easeOut and disables when disableAnimations=true',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: ScaleTap(
                onTap: () => tapped = true,
                child: const SizedBox(width: 120, height: 48, child: Text('Card')),
              ),
            ),
          ),
        ),
      );

      final scaleFinder = find.byType(AnimatedScale);
      expect(scaleFinder, findsOneWidget);
      var widget = tester.widget<AnimatedScale>(scaleFinder);
      expect(widget.duration, const Duration(milliseconds: 120));
      expect(widget.curve, Curves.easeOut);
      expect(widget.scale, 1.0);

      final gesture = await tester.startGesture(tester.getCenter(find.text('Card')));
      await tester.pump();
      widget = tester.widget<AnimatedScale>(scaleFinder);
      expect(widget.scale, 0.98);

      await gesture.up();
      await tester.pumpAndSettle();
      widget = tester.widget<AnimatedScale>(scaleFinder);
      expect(widget.scale, 1.0);
      expect(tapped, isTrue);

      // 减少动画模式：时长退化为 Duration.zero，按下不缩放
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: ScaleTap(
                  onTap: () {},
                  child: const SizedBox(width: 120, height: 48, child: Text('Reduced')),
                ),
              ),
            ),
          ),
        ),
      );

      final reducedGesture = await tester.startGesture(tester.getCenter(find.text('Reduced')));
      await tester.pump();
      final reducedScale = tester.widget<AnimatedScale>(scaleFinder);
      expect(reducedScale.duration, Duration.zero);
      expect(reducedScale.scale, 1.0);
      await reducedGesture.up();
      await tester.pump();
    });

    testWidgets('BreathingDot becomes static when disableAnimations=true', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: BreathingDot(color: Colors.teal, size: 8)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BreathingDot), findsOneWidget);
      expect(find.byType(Transform), findsNothing);
    });

    testWidgets('M3SlidingNavBar uses 250ms 64x32 sliding pill and 24->28 icon scale',
        (tester) async {
      var selected = 0;
      Widget buildBar({required bool disableAnimations}) {
        return MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            disableAnimations: disableAnimations,
          ),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  bottomNavigationBar: M3SlidingNavBar(
                    selectedIndex: selected,
                    onDestinationSelected: (i) => setState(() => selected = i),
                    destinations: const [
                      M3NavDestination(icon: Icons.today_rounded, label: 'Today', color: Colors.blue),
                      M3NavDestination(
                        icon: Icons.calendar_month_rounded,
                        label: 'Schedule',
                        color: Colors.indigo,
                      ),
                      M3NavDestination(
                        icon: Icons.restaurant_rounded,
                        label: 'Diet',
                        color: Colors.green,
                      ),
                      M3NavDestination(
                        icon: Icons.fitness_center_rounded,
                        label: 'Workout',
                        color: Colors.orange,
                      ),
                      M3NavDestination(
                        icon: Icons.smart_toy_rounded,
                        label: 'AI',
                        color: Colors.purple,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }

      await tester.pumpWidget(buildBar(disableAnimations: false));
      await tester.pumpAndSettle();

      final pillFinder = find.byKey(const ValueKey('m3_nav_sliding_pill'));
      var pill = tester.widget<AnimatedPositioned>(pillFinder);
      expect(pill.width, 64);
      expect(pill.height, 32);
      expect(pill.duration, const Duration(milliseconds: 250));
      expect(pill.curve, Curves.easeInOutCubicEmphasized);
      final initialLeft = pill.left!;

      final iconsBefore = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(iconsBefore[0].size, 28.0);
      expect(iconsBefore[1].size, 24.0);

      await tester.tap(find.text('Diet'));
      await tester.pumpAndSettle();

      expect(selected, 2);
      pill = tester.widget<AnimatedPositioned>(pillFinder);
      expect(pill.left!, greaterThan(initialLeft));
      final iconsAfter = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(iconsAfter[0].size, 24.0);
      expect(iconsAfter[2].size, 28.0);

      // 减少动画模式：pill 动画时长退化为 Duration.zero
      await tester.pumpWidget(buildBar(disableAnimations: true));
      await tester.pump();
      pill = tester.widget<AnimatedPositioned>(pillFinder);
      expect(pill.duration, Duration.zero);
    });

    test('AppTheme registers M3SubtlePageTransitionsBuilder for mobile platforms', () {
      final lightBuilders = AppTheme.light().pageTransitionsTheme.builders;
      final darkBuilders = AppTheme.dark().pageTransitionsTheme.builders;
      expect(lightBuilders[TargetPlatform.android], isA<M3SubtlePageTransitionsBuilder>());
      expect(lightBuilders[TargetPlatform.iOS], isA<M3SubtlePageTransitionsBuilder>());
      expect(darkBuilders[TargetPlatform.android], isA<M3SubtlePageTransitionsBuilder>());
    });
  });
}
