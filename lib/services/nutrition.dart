import '../models/models.dart';

/// 营养与能量计算（含 MET 运动消耗公式与动态热量调整）。
class Nutrition {
  Nutrition._();

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

  /// MET 消耗估算：kcal = MET × 体重(kg) × 时长(小时)
  static double calcMetCalories({required double met, required double weightKg, required double minutes}) {
    if (minutes <= 0) return 0;
    return met * weightKg * (minutes / 60.0);
  }

  /// 基础代谢 BMR（Mifflin-St Jeor 公式）
  static double bmr(Profile p, double weightKg) {
    final base = 10 * weightKg + 6.25 * p.height - 5 * p.age;
    return p.gender == 'female' ? base - 161 : base + 5;
  }

  /// 静息 + 日常活动消耗（不含当日额外训练）：BMR × 活动系数
  static double tdee(Profile p, double weightKg) => bmr(p, weightKg) * p.activity;

  /// 每日动态热量目标：
  /// 每日总消耗 = BMR × 活动系数 + 当日训练消耗(workoutBurn)
  /// 减脂：-18%（介于 15%~20%），增肌：+12%（介于 10%~15%），维持/提升体能：±0
  static double calorieTarget(Profile p, double weightKg, {double workoutBurn = 0}) {
    final totalBurn = tdee(p, weightKg) + workoutBurn;
    switch (p.goal) {
      case 'lose':
        return totalBurn * 0.82;
      case 'gain':
        return totalBurn * 1.12;
      default:
        return totalBurn;
    }
  }

  /// 三大营养素目标（克）：减脂 2.0g/kg 蛋白质，增肌 1.9g/kg，维持 1.6g/kg；脂肪占 25% 热量，其余碳水
  static ({double protein, double carbs, double fat}) macroTargets(
    Profile p,
    double weightKg, {
    double workoutBurn = 0,
  }) {
    final kcal = calorieTarget(p, weightKg, workoutBurn: workoutBurn);
    final proteinPerKg = p.goal == 'lose'
        ? 2.0
        : (p.goal == 'gain' ? 1.9 : 1.6);
    final protein = weightKg * proteinPerKg;
    final fat = kcal * 0.25 / 9;
    final carbs = ((kcal - protein * 4 - fat * 9) / 4).clamp(0, double.infinity).toDouble();
    return (protein: protein, carbs: carbs, fat: fat);
  }

  static double bmi(double heightCm, double weightKg) {
    final h = heightCm / 100;
    return weightKg / (h * h);
  }

  static String bmiLabel(double bmi) {
    if (bmi < 18.5) return '偏瘦';
    if (bmi < 24) return '正常';
    if (bmi < 28) return '超重';
    return '肥胖';
  }
}
