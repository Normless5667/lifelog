import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// 营养与能量计算（含 MET 运动消耗公式、动态热量调整与全链路数值合理性钳制）。
class Nutrition {
  Nutrition._();

  static const double maxSetWeightKg = 500.0;
  static const int maxSetReps = 100;
  static const double maxSessionVolumeKg = 100000.0;
  static const double maxSingleMealCalories = 20000.0;
  static const double maxDailyCalories = 50000.0;
  static const double maxSingleMealMacroG = 2000.0;
  static const double maxDailyMacroG = 5000.0;
  static const double maxSingleActivityBurnKcal = 10000.0;
  static const double maxDailyWorkoutBurnKcal = 15000.0;

  /// 力量训练两段式消耗估算系数：
  /// - 0.008 kcal/kg：抗阻训练每完成 1 kg 容量净消耗约 0.007–0.010 kcal
  /// - 2.0 kcal/组：准备、调器械、组间走动等每组固定开销
  /// - 单次自动估算上限 800 kcal；用户手动修正单次上限 3000 kcal
  static const double strengthVolumeKcalPerKg = 0.008;
  static const double strengthPerSetOverheadKcal = 2.0;
  static const double maxAutoStrengthBurnKcal = 800.0;
  static const double maxManualWorkoutBurnKcal = 3000.0;

  static final RegExp _plainDecimalRe = RegExp(r'^\d+(\.\d+)?$');
  static final RegExp _plainIntRe = RegExp(r'^\d+$');

  /// 仅解析普通非负十进制小数，拒绝科学计数法（如 7.3e5）、负号、NaN/Infinity。
  static double? parsePlainDouble(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !_plainDecimalRe.hasMatch(t)) return null;
    final v = double.tryParse(t);
    if (v == null || !v.isFinite) return null;
    return v;
  }

  /// 仅解析普通非负整数，拒绝科学计数法、小数、负号或非法字符。
  static int? parsePlainInt(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !_plainIntRe.hasMatch(t)) return null;
    return int.tryParse(t);
  }

  /// 单组力量训练合理性校验：必须同时具备有效重量 (0, 500] kg 与次数 (0, 100]。
  static bool isValidStrengthSet(double weightKg, int reps) {
    return weightKg.isFinite &&
        weightKg > 0 &&
        weightKg <= maxSetWeightKg &&
        reps > 0 &&
        reps <= maxSetReps;
  }

  /// 计算力量训练正式组数与总容量（自动排除热身组与超限异常组；总容量超 100000 kg 归零兜底）。
  static ({int sets, double volume}) calcStrengthStats(
    Iterable<({double weight, int reps, bool isWarmup})> rows,
  ) {
    var workSets = 0;
    var vol = 0.0;
    for (final s in rows) {
      if (s.isWarmup) continue;
      if (!isValidStrengthSet(s.weight, s.reps)) continue;
      workSets++;
      vol += s.weight * s.reps;
    }
    if (!vol.isFinite || vol > maxSessionVolumeKg) {
      debugPrint('[Nutrition] Abnormal workout volume detected ($vol kg), clamped to 0.');
      vol = 0;
    }
    return (sets: workSets, volume: vol);
  }

  /// 两段式力量训练消耗估算：
  /// 1) 容量法（主依据，适合批量补录）：totalVolumeKg × 0.008 + workSets × 2.0
  /// 2) 计时法（辅助，适合真实连续训练）：MET × weightKg × (elapsedMinutes / 60)
  /// 取二者较大值，并封顶于 800 kcal/次。
  static double estimateStrengthBurnKcal({
    required double totalVolumeKg,
    required int workSets,
    required double weightKg,
    required double elapsedMinutes,
  }) {
    final safeVol = (totalVolumeKg.isFinite && totalVolumeKg > 0)
        ? totalVolumeKg.clamp(0.0, maxSessionVolumeKg).toDouble()
        : 0.0;
    final safeSets = workSets > 0 ? workSets.clamp(0, 500) : 0;
    final byVolume =
        safeVol * strengthVolumeKcalPerKg + safeSets * strengthPerSetOverheadKcal;
    final safeMins = (elapsedMinutes.isFinite && elapsedMinutes > 0)
        ? elapsedMinutes.clamp(0.0, 180.0).toDouble()
        : 0.0;
    final byTime = calcMetCalories(
      met: strengthMet,
      weightKg: weightKg,
      minutes: safeMins,
    );
    final result = byVolume > byTime ? byVolume : byTime;
    return result.clamp(0.0, maxAutoStrengthBurnKcal).toDouble();
  }

  /// 统一计算某次力量训练消耗（严格优先级，算法调整绝不覆盖用户手改值）：
  /// 1) manualBurnKcal（用户手动填写热量，最高优先）
  /// 2) manualDurationMin（用户手动填写时长，按力量 MET 重算）
  /// 3) 自动估算（容量法与计时法取大）
  static double burnForWorkout({
    required Workout workout,
    required double totalVolumeKg,
    required int workSets,
    required double weightKg,
    double? overrideElapsedMinutes,
  }) {
    if (workout.manualBurnKcal != null &&
        workout.manualBurnKcal!.isFinite &&
        workout.manualBurnKcal! > 0) {
      return workout.manualBurnKcal!.clamp(0.0, maxManualWorkoutBurnKcal).toDouble();
    }
    if (workout.manualDurationMin != null && workout.manualDurationMin! > 0) {
      return calcMetCalories(
        met: strengthMet,
        weightKg: weightKg,
        minutes: workout.manualDurationMin!.toDouble().clamp(1.0, 600.0),
      ).clamp(0.0, maxManualWorkoutBurnKcal).toDouble();
    }
    double elapsedMins = overrideElapsedMinutes ?? 0;
    if (overrideElapsedMinutes == null &&
        workout.endTime != null &&
        workout.endTime! > workout.startTime) {
      elapsedMins = (workout.endTime! - workout.startTime) / 60000.0;
    }
    if (elapsedMins <= 0 && workSets <= 0 && totalVolumeKg <= 0) return 0;
    return estimateStrengthBurnKcal(
      totalVolumeKg: totalVolumeKg,
      workSets: workSets,
      weightKg: weightKg,
      elapsedMinutes: elapsedMins,
    );
  }

  /// 统一计算有氧记录消耗（支持 manual_burn_kcal > manual_duration_min > calories/MET 优先级）
  static double burnForCardio(CardioRecord c, {required double weightKg}) {
    if (c.manualBurnKcal != null && c.manualBurnKcal!.isFinite && c.manualBurnKcal! > 0) {
      return c.manualBurnKcal!.clamp(0.0, maxManualWorkoutBurnKcal).toDouble();
    }
    if (c.manualDurationMin != null &&
        c.manualDurationMin!.isFinite &&
        c.manualDurationMin! > 0) {
      final met = cardioMets[c.type] ?? 5.0;
      return calcMetCalories(
        met: met,
        weightKg: weightKg,
        minutes: c.manualDurationMin!,
      );
    }
    if (c.calories.isFinite && c.calories > 0) {
      return c.calories.clamp(0.0, maxSingleActivityBurnKcal).toDouble();
    }
    final met = cardioMets[c.type] ?? 5.0;
    return calcMetCalories(
      met: met,
      weightKg: weightKg,
      minutes: c.durationMinutes,
    );
  }

  /// 步数折算消耗（kcal）：步数钳制 [0, 200000]，体重钳制 [20, 300] kg，结果上限 10000 kcal。
  static double calcStepCalories({required int steps, required double weightKg}) {
    if (steps <= 0 || !weightKg.isFinite || weightKg <= 0) return 0;
    final safeSteps = steps.clamp(0, 200000);
    final safeWeight = weightKg.clamp(20.0, 300.0);
    return ((safeSteps / 1000.0) * (safeWeight * 0.55))
        .clamp(0.0, maxSingleActivityBurnKcal)
        .toDouble();
  }

  static double clampMealCalories(double kcal) {
    if (!kcal.isFinite || kcal <= 0) return 0;
    return kcal.clamp(0.0, maxSingleMealCalories).toDouble();
  }

  static double clampMealMacro(double grams) {
    if (!grams.isFinite || grams <= 0) return 0;
    return grams.clamp(0.0, maxSingleMealMacroG).toDouble();
  }

  static double? sanitizeWeightKg(double? w) {
    if (w == null || !w.isFinite || w <= 0) return null;
    return w.clamp(15.0, 350.0).toDouble();
  }

  static double? sanitizeBodyFat(double? fat) {
    if (fat == null || !fat.isFinite || fat <= 0) return null;
    return fat.clamp(2.0, 70.0).toDouble();
  }

  static double? sanitizeWaistCm(double? waist) {
    if (waist == null || !waist.isFinite || waist <= 0) return null;
    return waist.clamp(30.0, 220.0).toDouble();
  }

  static double weightDeltaKg(double latestKg, double previousKg) {
    if (!latestKg.isFinite || !previousKg.isFinite || latestKg <= 0 || previousKg <= 0) {
      return 0;
    }
    final a = latestKg.clamp(15.0, 350.0);
    final b = previousKg.clamp(15.0, 350.0);
    return (a - b).clamp(-100.0, 100.0).toDouble();
  }

  static final activityLevels = <double, String>{
    1.2: '久坐（几乎不运动）',
    1.375: '轻度（每周运动 1-3 天）',
    1.55: '中度（每周运动 3-5 天）',
    1.725: '高强度（每周运动 6-7 天）',
    1.9: '极高（体力劳动 / 一天两练）',
  };

  static const goals = <String, String>{
    'lose': '减脂',
    'maintain': '维持',
    'gain': '增肌',
    'fitness': '提升体能',
  };

  static const experiences = <String, String>{
    'none': '零基础',
    'beginner': '半年以内',
    'intermediate': '1-3 年',
    'advanced': '3 年以上',
  };

  static const equipments = <String, String>{
    'bodyweight': '徒手',
    'dumbbell': '哑铃',
    'barbell': '杠铃',
    'gym': '健身房全套',
  };

  /// 有氧运动 MET 表（kcal = MET × 体重kg × 小时；兼容新统一英文 key 与历史中文 key）
  static final cardioMets = <String, double>{
    '走路': 3.5,
    '快走': 4.3,
    '慢跑': 7.0,
    '中速跑': 9.8,
    '骑行': 7.5,
    '游泳': 8.0,
    '跳绳': 12.3,
    '其他': 5.0,
    CardioType.walk: 3.5,
    CardioType.run: 8.0,
    CardioType.cycle: 7.5,
    CardioType.swim: 8.0,
    CardioType.jumpRope: 12.3,
    CardioType.other: 5.0,
  };

  /// 跑步热量估算（runs 与 cardio_records 唯一权威口径）：
  /// - 有 GPS 距离时按配速分档：kcal = distanceKm × weightKg × factor
  ///   配速 < 5.0 分/公里 -> 1.15（快跑）
  ///   配速 < 6.5 分/公里 -> 1.08（中速）
  ///   配速 > 8.0 分/公里 -> 0.95（慢跑/走跑交替）
  ///   其余 -> 1.036
  /// - 无 GPS 距离（室内跑或信号差）时退回 MET 7.0 兜底，不为 0
  static double estimateRunKcal({
    required double distanceKm,
    required double weightKg,
    required int durationSecs,
  }) {
    if (!weightKg.isFinite || weightKg <= 0) return 0;
    final w = weightKg.clamp(20.0, 300.0).toDouble();
    if (distanceKm.isFinite && distanceKm > 0.02) {
      double factor = 1.036;
      if (durationSecs > 0) {
        final paceMinPerKm = (durationSecs / 60.0) / distanceKm;
        if (paceMinPerKm < 5.0) {
          factor = 1.15;
        } else if (paceMinPerKm < 6.5) {
          factor = 1.08;
        } else if (paceMinPerKm > 8.0) {
          factor = 0.95;
        }
      }
      return (distanceKm * w * factor)
          .roundToDouble()
          .clamp(0.0, maxSingleActivityBurnKcal)
          .toDouble();
    }
    if (durationSecs <= 0) return 0;
    return calcMetCalories(
      met: 7.0,
      weightKg: w,
      minutes: durationSecs / 60.0,
    ).roundToDouble();
  }

  static const strengthMet = 5.0;

  /// MET 消耗估算：kcal = MET × 体重(kg) × 时长(小时)，带合理性钳制
  static double calcMetCalories({required double met, required double weightKg, required double minutes}) {
    if (!met.isFinite || !weightKg.isFinite || !minutes.isFinite) return 0;
    if (met <= 0 || weightKg <= 0 || minutes <= 0) return 0;
    final safeMet = met.clamp(0.5, 25.0);
    final safeWeight = weightKg.clamp(20.0, 300.0);
    final safeMins = minutes.clamp(0.0, 1440.0);
    return (safeMet * safeWeight * (safeMins / 60.0))
        .clamp(0.0, maxSingleActivityBurnKcal)
        .toDouble();
  }

  /// 基础代谢 BMR（Mifflin-St Jeor 公式，输入与输出合理性钳制）
  static double bmr(Profile p, double weightKg) {
    final safeWeight = (weightKg.isFinite && weightKg > 0 ? weightKg : 60.0).clamp(20.0, 300.0);
    final safeHeight = (p.height.isFinite && p.height > 0 ? p.height : 170.0).clamp(80.0, 250.0);
    final safeAge = p.age.clamp(10, 120);
    final base = 10 * safeWeight + 6.25 * safeHeight - 5 * safeAge;
    final raw = p.gender == 'female' ? base - 161 : base + 5;
    return raw.clamp(500.0, 6000.0).toDouble();
  }

  /// 静息 + 日常活动消耗（不含当日额外训练）：BMR × 活动系数
  static double tdee(Profile p, double weightKg) {
    final safeAct = (p.activity.isFinite && p.activity > 0 ? p.activity : 1.55).clamp(1.0, 2.5);
    return (bmr(p, weightKg) * safeAct).clamp(600.0, 10000.0).toDouble();
  }

  /// 每日动态热量目标：
  /// 每日总消耗 = BMR × 活动系数 + 当日训练消耗(workoutBurn)
  /// 减脂：-18%（介于 15%~20%），增肌：+12%（介于 10%~15%），维持/提升体能：±0
  static double calorieTarget(Profile p, double weightKg, {double workoutBurn = 0}) {
    final safeBurn = (workoutBurn.isFinite && workoutBurn > 0 ? workoutBurn : 0.0)
        .clamp(0.0, maxSingleActivityBurnKcal);
    final totalBurn = tdee(p, weightKg) + safeBurn;
    final double raw;
    switch (p.goal) {
      case 'lose':
        raw = totalBurn * 0.82;
        break;
      case 'gain':
        raw = totalBurn * 1.12;
        break;
      default:
        raw = totalBurn;
    }
    return raw.clamp(800.0, 12000.0).toDouble();
  }

  /// 三大营养素目标（克）：减脂 2.0g/kg 蛋白质，增肌 1.9g/kg，维持 1.6g/kg；脂肪占 25% 热量，其余碳水
  static ({double protein, double carbs, double fat}) macroTargets(
    Profile p,
    double weightKg, {
    double workoutBurn = 0,
  }) {
    final safeWeight = (weightKg.isFinite && weightKg > 0 ? weightKg : 60.0).clamp(20.0, 300.0);
    final kcal = calorieTarget(p, safeWeight, workoutBurn: workoutBurn);
    final proteinPerKg = p.goal == 'lose'
        ? 2.0
        : (p.goal == 'gain' ? 1.9 : 1.6);
    final protein = (safeWeight * proteinPerKg).clamp(20.0, 600.0).toDouble();
    final fat = (kcal * 0.25 / 9).clamp(15.0, 400.0).toDouble();
    final carbs = ((kcal - protein * 4 - fat * 9) / 4).clamp(0.0, 2000.0).toDouble();
    return (protein: protein, carbs: carbs, fat: fat);
  }

  static double bmi(double heightCm, double weightKg) {
    if (!heightCm.isFinite || !weightKg.isFinite || heightCm <= 0 || weightKg <= 0) {
      return 0;
    }
    final h = heightCm.clamp(50.0, 260.0) / 100.0;
    final w = weightKg.clamp(15.0, 350.0);
    return (w / (h * h)).clamp(5.0, 100.0).toDouble();
  }

  static String bmiLabel(double bmi) {
    if (bmi < 18.5) return '偏瘦';
    if (bmi < 24) return '正常';
    if (bmi < 28) return '超重';
    return '肥胖';
  }
}
