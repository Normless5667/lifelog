import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/screens/diet/meal_edit_dialog.dart';
import 'package:lifelog/screens/workout/workout_session_screen.dart';
import 'package:lifelog/services/ai_service.dart';
import 'package:lifelog/services/usage_telemetry_service.dart';
import 'package:lifelog/widgets/in_progress_workout_card.dart';

void main() {
  group('P0 Workout Timer lifecycle & InProgressWorkoutCard', () {
    testWidgets('inactive does not pause timer; paused -> resumed catches up from wall clock',
        (tester) async {
      final startMs = DateTime.now().millisecondsSinceEpoch - 125 * 1000; // started 2m05s ago
      final workout = Workout(id: 99, date: '2026-11-20', startTime: startMs);
      final bench = Exercise(id: 1, name: '杠铃卧推', category: '胸');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: WorkoutSessionScreen(
            workoutId: 99,
            isNew: true,
            initialWorkoutForTest: workout,
            initialBlocksForTest: [
              (
                exercise: bench,
                sets: [
                  WorkoutSet(workoutId: 99, exerciseId: 1, setIndex: 1, weight: 60, reps: 10),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // In debug mode, timer badge shows F1R1
      expect(find.textContaining('F1R1'), findsOneWidget);

      // Simulate notification shade / edge gesture -> inactive MUST NOT flip F1 to F0
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('F1R1'), findsOneWidget);

      // Dismiss notification shade -> back to resumed directly
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.textContaining('F1R1'), findsOneWidget);

      // Simulate true Android background sequence: inactive -> hidden -> paused -> hidden -> inactive -> resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.textContaining('F1R1'), findsOneWidget);
      expect(find.textContaining('02:'), findsOneWidget);

      // Cleanly unmount so periodic timer is disposed
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('InProgressWorkoutCard displays live stats, stale threshold (6h), and actions',
        (tester) async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final freshSnap = InProgressWorkoutSnapshot(
        workout: Workout(id: 10, date: '2026-11-20', startTime: nowMs - 2696 * 1000), // 44:56
        exerciseNames: const ['杠铃卧推'],
        workSets: 20,
        volume: 5704,
        estCalories: 120,
      );
      expect(freshSnap.isStaleAt(nowMs), isFalse);

      final staleSnap = InProgressWorkoutSnapshot(
        workout: Workout(id: 11, date: '2026-11-20', startTime: nowMs - 7 * 3600 * 1000),
        exerciseNames: const ['杠铃卧推'],
        workSets: 5,
        volume: 1200,
        estCalories: 40,
      );
      expect(staleSnap.isStaleAt(nowMs), isTrue);

      var resumed = false;
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: InProgressWorkoutCard(
              snapshot: freshSnap,
              onResume: () => resumed = true,
              onFinish: () => finished = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('训练进行中'), findsOneWidget);
      expect(find.textContaining('20 组'), findsOneWidget);
      expect(find.textContaining('5704 kg'), findsOneWidget);
      expect(find.textContaining('44:5'), findsOneWidget);

      await tester.tap(find.text('继续训练'));
      await tester.pump();
      expect(resumed, isTrue);

      await tester.tap(find.text('结束并保存'));
      await tester.pump();
      expect(finished, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('P1/P2 Telemetry summary consistency, AI plan JSON repair & Quick Diet', () {
    test('summarizeEvents aligns frame_jank events vs frames, sums timer_active_sec, isolates step_sync',
        () {
      final ts = DateTime(2026, 11, 20, 12, 0).millisecondsSinceEpoch;
      final rows = <Map<String, Object?>>[
        // 2 frame_jank events representing 3 + 5 = 8 dropped frames
        {
          'ts': ts,
          'category': 'perf',
          'name': 'frame_jank',
          'value': 3.0,
          'extra': jsonEncode({'jank_count': 3, 'max_frame_ms': 28.5}),
        },
        {
          'ts': ts + 3000,
          'category': 'perf',
          'name': 'frame_jank',
          'value': 5.0,
          'extra': jsonEncode({'jank_count': 5, 'max_frame_ms': 44.2}),
        },
        // Cumulative active timer seconds (new timer_active_sec + legacy timer_tick)
        {
          'ts': ts + 6000,
          'category': 'perf',
          'name': 'timer_active_sec',
          'duration_ms': 1800000, // 1800s
          'value': 1800.0,
        },
        {
          'ts': ts + 9000,
          'category': 'perf',
          'name': 'timer_tick',
          'duration_ms': 900000, // 900s
          'value': 900.0,
        },
        // Background step_sync (both new system category & legacy feature category) must NOT enter feature_conversion
        {'ts': ts, 'category': 'system', 'name': 'step_sync', 'action': 'success'},
        {'ts': ts, 'category': 'feature', 'name': 'step_sync', 'action': 'success'},
        // Genuine feature conversion: start_workout 1 tap / 1 success -> rate 1.0
        {'ts': ts, 'category': 'feature', 'name': 'start_workout', 'action': 'tap'},
        {'ts': ts, 'category': 'feature', 'name': 'start_workout', 'action': 'success'},
      ];

      final summary = UsageTelemetryService.summarizeEvents(rows, extraLiveTimerSec: 30);
      final perf = summary['perf'] as Map<String, dynamic>;
      expect(perf['jank_events'], 2);
      expect(perf['jank_frames'], 8);
      expect(perf['max_jank_ms'], 44.2);
      expect(perf['timer_active_seconds'], 2730); // 1800 + 900 + 30

      final conv = (summary['feature_conversion'] as List).cast<Map<String, dynamic>>();
      expect(conv.any((e) => e['feature'] == 'step_sync'), isFalse);
      final sw = conv.firstWhere((e) => e['feature'] == 'start_workout');
      expect(sw['tap'], 1);
      expect(sw['success'], 1);
      expect(sw['rate'], 1.0);

      final sys = summary['system_tasks'] as Map<String, dynamic>;
      expect((sys['step_sync'] as Map)['success'], 2);
    });

    test('AiService.extractJson repairs trailing commas and smart quotes in workout plans', () {
      const messyPlanJson = '''
      ```json
      {
        “plan_name”: "推拉腿三分化",
        "days": [
          {
            "day": "周一",
            "focus": "推",
            "exercises": [
              {"name": "杠铃卧推", "sets": 4, "reps": "8-10", "weight_hint": "60kg",},
            ],
          },
        ],
      }
      ```
      ''';
      final parsed = AiService.extractJson(messyPlanJson);
      expect(parsed, isNotNull);
      final plan = TrainingPlan.fromJson(parsed!);
      expect(plan.planName, '推拉腿三分化');
      expect(plan.days.length, 1);
      expect(plan.days.first.exercises.first.name, '杠铃卧推');
    });

    testWidgets('MealEditDialog 1-tap recent meal chip fills and saves immediately', (tester) async {
      Meal? saved;
      final recent = [
        Meal(
          date: '2026-11-19',
          mealType: 1,
          name: '鸡胸肉沙拉',
          amount: '1份',
          calories: 420,
          protein: 38,
          carbs: 28,
          fat: 14,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  saved = await showDialog<Meal>(
                    context: context,
                    builder: (_) => MealEditDialog(
                      date: '2026-11-20',
                      initialMealType: 1,
                      recentMeals: recent,
                    ),
                  );
                },
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      // Macros collapsed by default for fast entry
      expect(find.text('展开份量与三大营养素（可选）'), findsOneWidget);

      // 1-tap recent meal chip auto-fills and lets user save immediately
      await tester.tap(find.text('鸡胸肉沙拉 · 420 kcal'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.name, '鸡胸肉沙拉');
      expect(saved!.calories, 420);
      expect(saved!.protein, 38);
    });
  });
}
