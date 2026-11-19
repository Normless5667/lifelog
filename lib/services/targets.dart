import '../db/repo.dart';
import '../models/models.dart';
import '../utils/date_utils.dart';
import '../utils/l10n_ext.dart';
import 'nutrition.dart';
import 'step_service.dart';

class DailyTargets {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double bmr;
  final double baseTdee; // BMR × 活动系数
  final double workoutBurn; // 当日训练额外消耗（力量 + 有氧）
  final bool estimated; // true 表示缺少体重数据，用默认值

  const DailyTargets(
    this.calories,
    this.protein,
    this.carbs,
    this.fat, {
    this.bmr = 1600,
    this.baseTdee = 2000,
    this.workoutBurn = 0,
    this.estimated = false,
  });

  /// 根据资料、最新体重以及指定日期（默认今天）的训练与有氧消耗，动态计算每日目标。
  static Future<DailyTargets> load({String? date}) async {
    final targetDate = dateOnlyStr(date ?? today());
    final p = await Repo.getProfile();
    final rec = await Repo.latestBodyRecordWithWeight();
    final w = Nutrition.sanitizeWeightKg(rec?.weight) ?? 60.0;

    // 1) 当日有氧消耗（遵循 manualBurnKcal > manualDurationMin > calories/MET）
    final cardios = await Repo.getCardioRecords(date: targetDate);
    var burn = cardios.fold<double>(
      0,
      (s, c) => s + Nutrition.burnForCardio(c, weightKg: w),
    );

    // 2) 当日力量训练消耗（遵循 manualBurnKcal > manualDurationMin > 容量法/计时法取大）
    final exercises = await Repo.getExercises();
    final exMap = {for (final e in exercises) e.id: e};
    final workouts = await Repo.getWorkouts(date: targetDate);
    for (final wk in workouts) {
      final sets = await Repo.getSets(wk.id!);
      final strengthRows = <({double weight, int reps, bool isWarmup})>[];
      for (final s in sets) {
        final ex = exMap[s.exerciseId];
        if (ex != null && L10nHelper.isCardioCategory(ex.category)) continue;
        strengthRows.add((weight: s.weight, reps: s.reps, isWarmup: s.isWarmup));
      }
      final st = Nutrition.calcStrengthStats(strengthRows);
      burn += Nutrition.burnForWorkout(
        workout: wk,
        totalVolumeKg: st.volume,
        workSets: st.sets,
        weightKg: w,
      );
    }

    // 3) 当日计步传感器步数折算消耗
    if (targetDate == today()) {
      final stepState = await StepService.getTodaySteps(weightKg: w);
      burn += stepState.burnedKcal;
    } else {
      final savedSteps = int.tryParse(await Repo.getKv('steps_val_$targetDate') ?? '') ?? 0;
      burn += Nutrition.calcStepCalories(steps: savedSteps, weightKg: w);
    }
    burn = burn.clamp(0.0, Nutrition.maxDailyWorkoutBurnKcal).toDouble();

    final bmrVal = Nutrition.bmr(p, w);
    final baseTdeeVal = Nutrition.tdee(p, w);
    final m = Nutrition.macroTargets(p, w, workoutBurn: burn);
    return DailyTargets(
      Nutrition.calorieTarget(p, w, workoutBurn: burn),
      m.protein,
      m.carbs,
      m.fat,
      bmr: bmrVal,
      baseTdee: baseTdeeVal,
      workoutBurn: burn,
      estimated: rec == null || !(await Repo.hasProfile()),
    );
  }
}

class DayTotals {
  double calories = 0, protein = 0, carbs = 0, fat = 0;

  DayTotals.of(Iterable<Meal> meals) {
    for (final m in meals) {
      calories += Nutrition.clampMealCalories(m.calories);
      protein += Nutrition.clampMealMacro(m.protein);
      carbs += Nutrition.clampMealMacro(m.carbs);
      fat += Nutrition.clampMealMacro(m.fat);
    }
    calories = calories.clamp(0.0, Nutrition.maxDailyCalories).toDouble();
    protein = protein.clamp(0.0, Nutrition.maxDailyMacroG).toDouble();
    carbs = carbs.clamp(0.0, Nutrition.maxDailyMacroG).toDouble();
    fat = fat.clamp(0.0, Nutrition.maxDailyMacroG).toDouble();
  }
}
