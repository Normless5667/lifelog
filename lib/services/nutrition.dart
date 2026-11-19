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

  /// 有氧运动 MET 表（kcal = MET × 体重kg × 小时）
  static final cardioMets = <String, double>{
    '走路': 3.5,
    '快走': 4.3,
    '慢跑': 7.0,
    '中速跑': 9.8,
    '骑行': 7.5,
    '游泳': 8.0,
    '跳绳': 12.3,
    '其他': 5.0,
  };

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
