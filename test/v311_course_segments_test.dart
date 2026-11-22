import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/db/repo.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/models/run_models.dart';
import 'package:lifelog/screens/running/run_detail_screen.dart';
import 'package:lifelog/screens/running/running_active_screen.dart';
import 'package:lifelog/services/nutrition.dart';
import 'package:lifelog/services/run_course_engine.dart';
import 'package:lifelog/services/running_tracker.dart';
import 'package:lifelog/widgets/common.dart';

void main() {
  late List<RunningCourse> allCourses;
  late RunningCourse fartlek3k;
  late RunningCourse distance3k;

  setUpAll(() async {
    final raw = File('assets/running_courses.json').readAsStringSync();
    allCourses = await RunningCourseCatalog.loadAll(overrideRawJson: raw);
    fartlek3k = allCourses.firstWhere((c) => c.id == 'fartlek_3k');
    distance3k = allCourses.firstWhere((c) => c.id == 'distance_3k');
  });

  group('v3.1.1 P0 RunCourseEngine: time-based, distance-based & 3x timeout guard', () {
    test('loads segmentTypes mapping from running_courses.json', () {
      expect(RunningCourseCatalog.segmentMeta('warmup').labelZh, '热身');
      expect(RunningCourseCatalog.segmentMeta('run').labelZh, '慢跑');
      expect(RunningCourseCatalog.segmentMeta('fast').labelZh, '快跑');
      expect(RunningCourseCatalog.segmentMeta('slow').labelZh, '慢跑恢复');
      expect(RunningCourseCatalog.segmentMeta('walk').labelZh, '快走');
      expect(RunningCourseCatalog.segmentMeta('cooldown').labelZh, '放松');
    });

    test('advances time-based course (3K Fartlek) accurately through all 9 segments to completion',
        () {
      final engine = RunCourseEngine(fartlek3k);
      expect(engine.totalSegments, 9);
      expect(engine.current!.type, 'warmup');
      expect(engine.remainingSecs, 300);

      // 28 秒后：还剩 04:32 (272 秒)
      final rMid = engine.tick(totalDistance: 50, totalSeconds: 28);
      expect(rMid.advanced, isFalse);
      expect(engine.remainingSecs, 272);
      expect(formatRunDuration(engine.remainingSecs!), '04:32');
      expect(engine.segmentProgress, closeTo(28 / 300, 0.001));

      // 第 300 秒：自动切到第 2 段「慢跑」(180s)
      final r2 = engine.tick(totalDistance: 450, totalSeconds: 300);
      expect(r2.advanced, isTrue);
      expect(r2.courseCompleted, isFalse);
      expect(r2.newSegment!.type, 'run');
      expect(engine.currentIndex, 1);
      expect(engine.next!.type, 'walk');
      expect(engine.next!.durationSeconds, 120);

      // 跑完剩余全部 8 段 -> 整门课程完成
      var elapsed = 300;
      var dist = 450.0;
      RunCourseTickResult last = r2;
      while (!engine.isCompleted) {
        final dur = engine.current!.durationSeconds!;
        elapsed += dur;
        dist += dur * 2.0;
        last = engine.tick(totalDistance: dist, totalSeconds: elapsed);
      }
      expect(last.courseCompleted, isTrue);
      expect(engine.isCompleted, isTrue);
      expect(engine.overallProgress, 1.0);
      expect(engine.buildSegmentRecords().length, 9);
    });

    test('advances distance-based course (3K Distance Split) by meters & enforces 3x timeout guard',
        () {
      final engine = RunCourseEngine(distance3k);
      expect(engine.totalSegments, 7);
      expect(engine.current!.type, 'warmup');
      expect(engine.remainingMeters, 400.0);

      // 跑 150 米：还剩 250 米
      final r1 = engine.tick(totalDistance: 150, totalSeconds: 60);
      expect(r1.advanced, isFalse);
      expect(engine.remainingMeters, closeTo(250.0, 0.01));
      expect(engine.segmentProgress, closeTo(150 / 400, 0.001));

      // 跑到 400 米：自动切到 800m 慢跑
      final r2 = engine.tick(totalDistance: 400, totalSeconds: 160);
      expect(r2.advanced, isTrue);
      expect(r2.forcedByTimeout, isFalse);
      expect(r2.newSegment!.type, 'run');
      expect(engine.remainingMeters, closeTo(800.0, 0.01));

      // 模拟 GPS 卡死：距离停在 420m 不动，用时超过 800m 基准时长（360s）的 3 倍（1080s）-> 强制切到下一段 400m 快跑
      final expected800 = RunCourseEngine.expectedSegmentDurationSecs(engine.current!);
      final rTimeout = engine.tick(
        totalDistance: 420,
        totalSeconds: 160 + expected800 * 3,
      );
      expect(rTimeout.advanced, isTrue);
      expect(rTimeout.forcedByTimeout, isTrue);
      expect(rTimeout.newSegment!.type, 'fast');
      expect(engine.currentIndex, 2);
    });
  });

  group('v3.1.1 P0 RunningActiveScreen course guidance UI, voice & save states', () {
    testWidgets(
        '3K Fartlek displays current segment, remaining 04:32, progress, next segment, switches & saves incomplete on early finish',
        (tester) async {
      final spoken = <String>[];
      final ctrl = RunningTrackerController(
        weightKg: 65.0,
        course: fartlek3k,
        onSpeakForTest: spoken.add,
      );
      await ctrl.start(skipPlatformSideEffects: true);

      RunRecord? savedRun;
      List<RunSegmentRecord>? savedSegments;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: RunningActiveScreen(
            weightKg: 65.0,
            course: fartlek3k,
            controllerForTest: ctrl,
            disableMapTilesForTest: true,
            onSaveRunOverrideForTest: (run, segs) async {
              savedRun = run;
              savedSegments = segs;
              return 77;
            },
          ),
        ),
      );
      await tester.pump();

      // 开跑即播报第一段热身语音
      expect(spoken, contains('先快走 5 分钟，让身体热起来'));

      // 推进到 28 秒 -> 显示「热身」「还剩 04:32」「第 1 段 / 共 9 段」与进度条
      ctrl.advanceTestClock(28);
      await tester.pump();
      expect(find.text('热身'), findsOneWidget);
      expect(find.text('还剩 04:32'), findsOneWidget);
      expect(find.text('第 1 段 / 共 9 段'), findsOneWidget);
      expect(find.byKey(const ValueKey('run_course_segment_progress_bar')), findsOneWidget);

      // 推进到 300 秒 -> 自动切到「慢跑」，显示「下一段：快走 120 秒」，横幅可见，语音念慢跑文案
      ctrl.advanceTestClock(300);
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('run_course_current_label'))).data,
        '慢跑',
      );
      expect(find.text('第 2 段 / 共 9 段'), findsOneWidget);
      expect(find.text('下一段：快走 120 秒'), findsOneWidget);
      expect(find.byKey(const ValueKey('run_course_transition_banner')), findsOneWidget);
      expect(spoken, contains('开始慢跑，保持能说话的节奏'));

      // 中途提前结束 -> 弹窗提示未完成，保存后 note == 'course_incomplete' 且分段入库
      await tester.tap(find.byKey(const ValueKey('run_finish_btn')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('未完成'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('run_confirm_save_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(savedRun, isNotNull);
      expect(savedRun!.courseId, 'fartlek_3k');
      expect(savedRun!.note, 'course_incomplete');
      expect(savedSegments, isNotNull);
      expect(savedSegments!.isNotEmpty, isTrue);
      expect(find.byType(RunDetailScreen), findsOneWidget);
      expect(find.text('未完成课程'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('distance-based course (distance_3k) switches by meters and marks completed at end',
        (tester) async {
      final spoken = <String>[];
      final ctrl = RunningTrackerController(
        weightKg: 65.0,
        course: distance3k,
        onSpeakForTest: spoken.add,
      );
      await ctrl.start(skipPlatformSideEffects: true);

      RunRecord? savedRun;
      List<RunSegmentRecord>? savedSegments;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: RunningActiveScreen(
            weightKg: 65.0,
            course: distance3k,
            controllerForTest: ctrl,
            disableMapTilesForTest: true,
            onSaveRunOverrideForTest: (run, segs) async {
              savedRun = run;
              savedSegments = segs;
              return 88;
            },
          ),
        ),
      );
      await tester.pump();

      // 初始第 1 段：热身，还剩 400 米，下一段：慢跑 800 米
      expect(find.text('热身'), findsOneWidget);
      expect(find.text('还剩 400 米'), findsOneWidget);
      expect(find.text('下一段：慢跑 800 米'), findsOneWidget);

      // 模拟 GPS 往前跑 420 米 -> 自动切到第 2 段「慢跑」
      const degPerMeterLat = 1.0 / 111195.0;
      const baseT = 1760000000000;
      for (var i = 0; i <= 42; i++) {
        ctrl.injectRawPoint(
          RoutePoint(
            lat: 20.9628 + i * 10.0 * degPerMeterLat,
            lng: 105.9410,
            t: baseT + i * 3000,
            accuracy: 6.0,
          ),
        );
      }
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('run_course_current_label'))).data,
        '慢跑',
      );
      expect(find.text('第 2 段 / 共 7 段'), findsOneWidget);
      expect(find.text('下一段：快跑 400 米'), findsOneWidget);

      // 快速走完剩余段到课程完成 -> 显示完成卡，保存后 note == 'course_completed'
      while (!ctrl.isCourseCompleted) {
        ctrl.skipCourseSegment();
      }
      await tester.pump();
      expect(find.byKey(const ValueKey('run_course_completed_card')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('run_finish_btn')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('run_confirm_save_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(savedRun, isNotNull);
      expect(savedRun!.note, 'course_completed');
      expect(savedSegments!.length, 7);
      expect(find.text('已完成课程'), findsOneWidget);

      ctrl.dispose();
    });
  });

  group('v3.1.1 P0 Run -> Cardio dual-write, pace-tiered calories & CardioType', () {
    test('Nutrition.estimateRunKcal applies pace-tiered factors and MET 7.0 indoor fallback', () {
      // 快跑：3km / 13min -> 配速 4.33 < 5.0 -> factor 1.15 -> 3 * 65 * 1.15 = 224.25 -> 224
      expect(
        Nutrition.estimateRunKcal(distanceKm: 3.0, weightKg: 65, durationSecs: 13 * 60),
        224.0,
      );
      // 中速：3km / 18min -> 配速 6.0 < 6.5 -> factor 1.08 -> 3 * 65 * 1.08 = 210.6 -> 211
      expect(
        Nutrition.estimateRunKcal(distanceKm: 3.0, weightKg: 65, durationSecs: 18 * 60),
        211.0,
      );
      // 标准：3km / 21min -> 配速 7.0 -> factor 1.036 -> 3 * 65 * 1.036 = 202.02 -> 202
      expect(
        Nutrition.estimateRunKcal(distanceKm: 3.0, weightKg: 65, durationSecs: 21 * 60),
        202.0,
      );
      // 慢跑/走跑交替：3km / 27min -> 配速 9.0 > 8.0 -> factor 0.95 -> 3 * 65 * 0.95 = 185.25 -> 185
      expect(
        Nutrition.estimateRunKcal(distanceKm: 3.0, weightKg: 65, durationSecs: 27 * 60),
        185.0,
      );
      // 室内无 GPS 距离兜底：MET 7.0 × 65kg × 0.5h = 227.5 -> 228（绝不为 0）
      expect(
        Nutrition.estimateRunKcal(distanceKm: 0.0, weightKg: 65, durationSecs: 30 * 60),
        228.0,
      );
    });

    test('buildLinkedCardioForRun preserves exact calories/duration/distance & source_run_id', () {
      final run = RunRecord(
        id: 19,
        date: '2026-11-20',
        startTime: 1760000000000,
        endTime: 1760001080000,
        durationSecs: 1080, // 18 min
        totalSecs: 1120,
        distanceM: 3000.0,
        avgPaceSecsPerKm: 360,
        caloriesKcal: 211,
        courseId: 'distance_3k',
      );
      final cardio = Repo.buildLinkedCardioForRun(run, runId: 19);
      expect(cardio.type, CardioType.run);
      expect(cardio.type, 'running');
      expect(CardioType.labelZh(cardio.type), '跑步');
      expect(cardio.sourceRunId, 19);
      expect(cardio.isFromRun, isTrue);
      expect(cardio.durationMinutes, closeTo(18.0, 0.001));
      expect(cardio.distanceKm, closeTo(3.0, 0.001));
      expect(cardio.calories, 211.0);
      // 饮食页走 Nutrition.burnForCardio() 取出的数字必须与 runs.caloriesKcal 完全一致
      expect(Nutrition.burnForCardio(cardio, weightKg: 65), 211.0);

      // toMap/fromMap 完整保留 source_run_id
      final restored = CardioRecord.fromMap(cardio.toMap());
      expect(restored.sourceRunId, 19);
      expect(restored.calories, 211.0);
    });
  });
}
