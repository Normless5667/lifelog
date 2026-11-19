import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/db/repo.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/screens/workout/workout_session_screen.dart';
import 'package:lifelog/services/nutrition.dart';
import 'package:lifelog/services/targets.dart';
import 'package:lifelog/utils/date_utils.dart';

void main() {
  group('Nutrition numeric parsing & sanity clamping', () {
    test('parsePlainDouble & parsePlainInt reject scientific notation and invalid strings', () {
      expect(Nutrition.parsePlainDouble('60'), 60.0);
      expect(Nutrition.parsePlainDouble('62.5'), 62.5);
      expect(Nutrition.parsePlainDouble(' 7.3e5 '), isNull);
      expect(Nutrition.parsePlainDouble('1E6'), isNull);
      expect(Nutrition.parsePlainDouble('-50'), isNull);
      expect(Nutrition.parsePlainDouble('NaN'), isNull);
      expect(Nutrition.parsePlainDouble('abc'), isNull);

      expect(Nutrition.parsePlainInt('10'), 10);
      expect(Nutrition.parsePlainInt('10.5'), isNull);
      expect(Nutrition.parsePlainInt('1e3'), isNull);
      expect(Nutrition.parsePlainInt('-2'), isNull);
    });

    test('calcStrengthStats enforces &&, warmup exclusion, per-set bounds, and 100000 kg cap', () {
      // Weight-only or reps-only sets must NOT be counted
      final partial = Nutrition.calcStrengthStats(const [
        (weight: 60.0, reps: 0, isWarmup: false),
        (weight: 0.0, reps: 10, isWarmup: false),
      ]);
      expect(partial.sets, 0);
      expect(partial.volume, 0);

      // Warmup and out-of-range sets (>500 kg or >100 reps) must be excluded
      final mixed = Nutrition.calcStrengthStats(const [
        (weight: 60.0, reps: 10, isWarmup: false), // valid: 600
        (weight: 60.0, reps: 10, isWarmup: true), // warmup: excluded
        (weight: 501.0, reps: 10, isWarmup: false), // >500kg: excluded
        (weight: 60.0, reps: 101, isWarmup: false), // >100 reps: excluded
        (weight: 732042.0, reps: 10, isWarmup: false), // absurd: excluded
      ]);
      expect(mixed.sets, 1);
      expect(mixed.volume, 600.0);

      // Volume exceeding 100,000 kg across many max-bound sets is clamped to 0
      final hugeSets = List.generate(
        5,
        (_) => (weight: 500.0, reps: 100, isWarmup: false), // 5 * 50,000 = 250,000 > 100,000
      );
      final clamped = Nutrition.calcStrengthStats(hugeSets);
      expect(clamped.sets, 5);
      expect(clamped.volume, 0.0);
    });

    test('Cross-module sanity clamps: diet totals, BMI/weight delta, cardio MET, step kcal', () {
      // Diet DayTotals clamping
      final totals = DayTotals.of([
        Meal(
          date: '2026-11-19',
          mealType: 0,
          name: 'Extreme meal',
          calories: 9999999,
          protein: double.nan,
          carbs: -50,
          fat: 50000,
        ),
        Meal(
          date: '2026-11-19',
          mealType: 1,
          name: 'Normal meal',
          calories: 600,
          protein: 35,
          carbs: 70,
          fat: 18,
        ),
      ]);
      expect(totals.calories, lessThanOrEqualTo(Nutrition.maxDailyCalories));
      expect(totals.calories, 20600.0);
      expect(totals.protein, 35.0);
      expect(totals.carbs, 70.0);
      expect(totals.fat, 2018.0);

      // BMI & weight delta clamping
      expect(Nutrition.bmi(0, 65), 0);
      expect(Nutrition.bmi(175, double.nan), 0);
      expect(Nutrition.bmi(175, 99999), lessThanOrEqualTo(100.0));
      expect(Nutrition.bmi(175, 70), closeTo(22.86, 0.05));
      expect(Nutrition.weightDeltaKg(999, 60).abs(), lessThanOrEqualTo(100.0));

      // Cardio MET & step calories clamping
      expect(
        Nutrition.calcMetCalories(met: 999, weightKg: 9999, minutes: 999999),
        lessThanOrEqualTo(Nutrition.maxSingleActivityBurnKcal),
      );
      expect(
        Nutrition.calcMetCalories(met: double.infinity, weightKg: 65, minutes: 30),
        0,
      );
      expect(
        Nutrition.calcStepCalories(steps: 99999999, weightKg: 9999),
        lessThanOrEqualTo(Nutrition.maxSingleActivityBurnKcal),
      );
      expect(
        Nutrition.calcStepCalories(steps: 10000, weightKg: 65),
        closeTo(357.5, 0.01),
      );
    });

    test('Strength burn two-stage estimator & manual adjustment priority', () {
      // Boss real-world case: 17 sets, 9004 kg, 2.78 min batch logging -> ~106 kcal (not 14!)
      final bossBurn = Nutrition.estimateStrengthBurnKcal(
        totalVolumeKg: 9004,
        workSets: 17,
        weightKg: 70,
        elapsedMinutes: 2.78,
      );
      expect(bossBurn, closeTo(106.032, 0.05));
      expect(bossBurn, greaterThanOrEqualTo(100));
      expect(bossBurn, lessThanOrEqualTo(150));

      // Continuous real-time workout (60 min, light volume) -> time MET wins (350 kcal)
      final continuousBurn = Nutrition.estimateStrengthBurnKcal(
        totalVolumeKg: 600,
        workSets: 3,
        weightKg: 70,
        elapsedMinutes: 60,
      );
      expect(continuousBurn, closeTo(350.0, 0.01));

      // Auto estimate cap at 800 kcal
      final cappedAuto = Nutrition.estimateStrengthBurnKcal(
        totalVolumeKg: 95000,
        workSets: 100,
        weightKg: 80,
        elapsedMinutes: 120,
      );
      expect(cappedAuto, 800.0);

      final startMs = DateTime(2026, 11, 19, 12, 0).millisecondsSinceEpoch;
      final endMs = startMs + 167000; // ~2.78 min

      // Priority 3: auto estimate when manual fields are null
      final autoWk = Workout(id: 1, date: '2026-11-19', startTime: startMs, endTime: endMs);
      expect(autoWk.isManuallyAdjusted, isFalse);
      expect(
        Nutrition.burnForWorkout(
          workout: autoWk,
          totalVolumeKg: 9004,
          workSets: 17,
          weightKg: 70,
        ),
        closeTo(106.032, 0.05),
      );

      // Priority 2: manualDurationMin (45 min -> 5.0 * 70 * 0.75 = 262.5 kcal)
      final durWk = Workout(
        id: 2,
        date: '2026-11-19',
        startTime: startMs,
        endTime: endMs,
        manualDurationMin: 45,
      );
      expect(durWk.isManuallyAdjusted, isTrue);
      expect(durWk.effectiveDurationMinutes, 45);
      expect(
        Nutrition.burnForWorkout(
          workout: durWk,
          totalVolumeKg: 9004,
          workSets: 17,
          weightKg: 70,
        ),
        closeTo(262.5, 0.01),
      );

      // Priority 1: manualBurnKcal (320 kcal) overrides both manualDurationMin and auto formula
      final burnWk = Workout(
        id: 3,
        date: '2026-11-19',
        startTime: startMs,
        endTime: endMs,
        manualDurationMin: 45,
        manualBurnKcal: 320,
      );
      expect(
        Nutrition.burnForWorkout(
          workout: burnWk,
          totalVolumeKg: 9004,
          workSets: 17,
          weightKg: 70,
        ),
        320.0,
      );

      // Serialization roundtrip preserves manual fields
      final restoredWk = Workout.fromMap(burnWk.toMap());
      expect(restoredWk.manualDurationMin, 45);
      expect(restoredWk.manualBurnKcal, 320.0);
      expect(restoredWk.isManuallyAdjusted, isTrue);

      // Cardio manual adjustment priority & roundtrip
      final cardio = CardioRecord(
        id: 5,
        date: '2026-11-19',
        type: '慢跑',
        durationMinutes: 20,
        calories: 163,
        manualDurationMin: 40,
        manualBurnKcal: 380,
      );
      expect(cardio.isManuallyAdjusted, isTrue);
      expect(cardio.effectiveDurationMinutes, 40);
      expect(Nutrition.burnForCardio(cardio, weightKg: 70), 380.0);
      final restoredCardio = CardioRecord.fromMap(cardio.toMap());
      expect(restoredCardio.manualDurationMin, 40);
      expect(restoredCardio.manualBurnKcal, 380.0);

      // Date normalization & reactive dataVersion tick
      expect(dateOnlyStr('2026-11-19T00:00:00.000'), '2026-11-19');
      expect(dateOnlyStr(' 2026-11-19 '), '2026-11-19');
      final beforeTick = Repo.dataVersion.value;
      Repo.notifyDataChanged();
      expect(Repo.dataVersion.value, beforeTick + 1);
    });
  });

  group('WorkoutSessionScreen interactive acceptance tests', () {
    Widget buildTestApp() {
      final workout = Workout(
        id: 1,
        date: '2026-11-19',
        startTime: DateTime(2026, 11, 19, 10, 0).millisecondsSinceEpoch,
      );
      final bench = Exercise(id: 1, name: '杠铃卧推', category: '胸');
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: WorkoutSessionScreen(
          workoutId: 1,
          isNew: true,
          initialWorkoutForTest: workout,
          initialBlocksForTest: [
            (
              exercise: bench,
              sets: [
                WorkoutSet(workoutId: 1, exerciseId: 1, setIndex: 1, weight: 0, reps: 0),
              ],
            ),
          ],
        ),
      );
    }

    testWidgets('kg & reps entry updates stats live (1 组 · 600 kg -> + -> 2 组 · 1200 kg), warmup excluded, cap enforced',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Verify Scaffold resizeToAvoidBottomInset is enabled
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.resizeToAvoidBottomInset, isTrue);

      // Initially 0 组 · 0 kg (with proper spaces)
      expect(find.text('0 组 · 0 kg'), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));

      // 1. Tap weight (kg) field and enter 60 -> still 0 sets until reps is also filled
      await tester.tap(fields.at(0));
      await tester.pump();
      await tester.enterText(fields.at(0), '60');
      await tester.pump();
      expect(find.text('60'), findsOneWidget);
      expect(find.text('0 组 · 0 kg'), findsOneWidget);

      // 2. Tap reps (次) field and enter 10 -> immediately updates to 1 组 · 600 kg
      await tester.tap(fields.at(1));
      await tester.pump();
      await tester.enterText(fields.at(1), '10');
      await tester.pump();
      expect(find.text('10'), findsOneWidget);
      expect(find.text('1 组 · 600 kg'), findsOneWidget);

      // 3. Tap + (加一组) -> copies 60 x 10 into a new set -> 2 组 · 1200 kg
      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.text('2 组 · 1200 kg'), findsOneWidget);

      // 4. Toggle row 2 warmup badge ('2' -> '热') -> excluded from volume/sets -> back to 1 组 · 600 kg
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.text('热'), findsOneWidget);
      expect(find.text('1 组 · 600 kg'), findsOneWidget);

      // Toggle warmup off again -> back to 2 组 · 1200 kg
      await tester.tap(find.text('热'));
      await tester.pumpAndSettle();
      expect(find.text('2 组 · 1200 kg'), findsOneWidget);

      // 5. Enter absurd weight (>500 kg) in row 2 -> excluded, volume never explodes
      await tester.enterText(find.byType(TextField).at(2), '999');
      await tester.pump();
      expect(find.text('1 组 · 600 kg'), findsOneWidget);
    });

    testWidgets('Starting rest timer hides rest-finished SnackBar so countdown and toast never coexist',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Simulate a lingering rest-finished SnackBar
      final ctx = tester.element(find.byType(Scaffold));
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('组间休息结束！开始下一组吧'),
          duration: Duration(seconds: 10),
        ),
      );
      await tester.pump();
      expect(find.text('组间休息结束！开始下一组吧'), findsOneWidget);

      // Tap start rest timer button
      await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
      await tester.pumpAndSettle();

      // Active rest countdown is shown AND the finished toast is dismissed
      expect(find.textContaining('01:30'), findsOneWidget);
      expect(find.text('组间休息结束！开始下一组吧'), findsNothing);
    });
  });
}
