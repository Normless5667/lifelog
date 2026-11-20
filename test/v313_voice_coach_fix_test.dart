import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/run_models.dart';
import 'package:lifelog/screens/running/running_active_screen.dart';
import 'package:lifelog/services/run_voice_coach.dart';
import 'package:lifelog/services/running_tracker.dart';
import 'package:lifelog/theme/app_theme.dart';

void main() {
  late RunningCourse fartlek3k;

  setUpAll(() async {
    final raw = File('assets/running_courses.json').readAsStringSync();
    final courses = await RunningCourseCatalog.loadAll(overrideRawJson: raw);
    fartlek3k = courses.firstWhere((c) => c.id == 'fartlek_3k');
  });

  group('v3.1.3 P0 RunVoiceCoach: retryable init & spaced speakSequence', () {
    test('init failure does NOT lock out retry; subsequent init succeeds', () async {
      var attempt = 0;
      final coach = RunVoiceCoach(
        customInitForTest: ({required bool isEnglish}) async {
          attempt++;
          if (attempt == 1) {
            throw Exception('TTS engine not ready');
          }
          return true;
        },
      );

      final first = await coach.init(isEnglish: false);
      expect(first, isFalse);
      expect(coach.isAvailable, isFalse);
      expect(coach.lastFailureReason, isNotNull);

      // 再次 init() 必须能重试并成功
      final second = await coach.init(isEnglish: false);
      expect(second, isTrue);
      expect(coach.isAvailable, isTrue);
      expect(coach.lastFailureReason, isNull);
      expect(attempt, 2);
    });

    test('speakSequence speaks lines sequentially with gap and never swallows line 2', () async {
      final spoken = <String>[];
      final timestamps = <DateTime>[];
      final coach = RunVoiceCoach(
        customInitForTest: ({required bool isEnglish}) async => true,
        customSpeakForTest: (text) async {
          spoken.add(text);
          timestamps.add(DateTime.now());
        },
      );
      await coach.init(isEnglish: false);

      await coach.speakSequence(
        ['开始 3 公里法特莱克跑，共 9 段，预计 29 分钟', '先快走 5 分钟，让身体热起来'],
        gap: const Duration(milliseconds: 60),
      );

      expect(spoken, [
        '开始 3 公里法特莱克跑，共 9 段，预计 29 分钟',
        '先快走 5 分钟，让身体热起来',
      ]);
      expect(
        timestamps[1].difference(timestamps[0]).inMilliseconds,
        greaterThanOrEqualTo(45),
      );
    });

    test('RunningTrackerController course start announces overview + first segment in order', () async {
      final spoken = <String>[];
      final ctrl = RunningTrackerController(
        weightKg: 65,
        course: fartlek3k,
        onSpeakForTest: spoken.add,
      );
      await ctrl.start(skipPlatformSideEffects: true);

      expect(spoken.length, greaterThanOrEqualTo(2));
      expect(spoken[0], contains('开始 3 公里法特莱克跑'));
      expect(spoken[0], contains('共 9 段'));
      expect(spoken[0], contains('预计 29 分钟'));
      expect(spoken[1], '先快走 5 分钟，让身体热起来');

      ctrl.dispose();
    });
  });

  group('v3.1.3 P0 RunningActiveScreen visible TTS unavailable dialog', () {
    testWidgets('shows visible prompt with Got It & Open Settings buttons when TTS unavailable',
        (tester) async {
      final ctrl = RunningTrackerController(
        weightKg: 65,
        course: fartlek3k,
        simulateVoiceUnavailableForTest: true,
      );
      await ctrl.start(skipPlatformSideEffects: true);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunningActiveScreen(
            weightKg: 65,
            course: fartlek3k,
            controllerForTest: ctrl,
            disableMapTilesForTest: true,
          ),
        ),
      );

      // 触发首帧 postFrameCallback 弹出不可用提示弹窗
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('run_voice_unavailable_dialog')), findsOneWidget);
      expect(find.text('语音播报不可用'), findsOneWidget);
      expect(find.byKey(const ValueKey('run_voice_unavailable_got_it')), findsOneWidget);
      expect(find.byKey(const ValueKey('run_voice_unavailable_settings')), findsOneWidget);

      // 点击「知道了」关闭弹窗后，跑步界面（含横幅与当前段卡片）照常可用
      await tester.tap(find.byKey(const ValueKey('run_voice_unavailable_got_it')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('run_voice_unavailable_dialog')), findsNothing);
      expect(find.text('热身'), findsOneWidget);

      ctrl.dispose();
    });
  });
}
