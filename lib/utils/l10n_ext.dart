import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/weather_service.dart';
import 'date_utils.dart';

extension L10nBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
  bool get isEnLocale => Localizations.localeOf(this).languageCode == 'en';
}

/// 根据食物名返回生动的 Emoji 图标
String foodEmoji(String name) {
  final n = name.toLowerCase();
  if (n.contains('鸡') || n.contains('chicken')) return '🍗';
  if (n.contains('牛') || n.contains('beef') || n.contains('steak')) return '🥩';
  if (n.contains('鱼') || n.contains('虾') || n.contains('海鲜') || n.contains('fish') || n.contains('shrimp')) return '🐟';
  if (n.contains('蛋') || n.contains('egg')) return '🍳';
  if (n.contains('奶') || n.contains('milk') || n.contains('豆浆')) return '🥛';
  if (n.contains('面') || n.contains('粉') || n.contains('noodle')) return '🍜';
  if (n.contains('饭') || n.contains('米') || n.contains('rice')) return '🍚';
  if (n.contains('面包') || n.contains('吐司') || n.contains('三明治') || n.contains('bread')) return '🥪';
  if (n.contains('菜') || n.contains('沙拉') || n.contains('西兰花') || n.contains('salad')) return '🥗';
  if (n.contains('果') || n.contains('香蕉') || n.contains('苹果') || n.contains('fruit') || n.contains('apple')) return '🍎';
  if (n.contains('咖啡') || n.contains('美式') || n.contains('拿铁') || n.contains('coffee')) return '☕';
  return '🍱';
}

/// 根据课程名返回专属图标
IconData courseIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('database') || n.contains('数据')) return Icons.storage_rounded;
  if (n.contains('machine') || n.contains('ai') || n.contains('算法')) return Icons.psychology_rounded;
  if (n.contains('ux') || n.contains('design') || n.contains('设计')) return Icons.palette_rounded;
  if (n.contains('english') || n.contains('英语')) return Icons.translate_rounded;
  if (n.contains('math') || n.contains('数学')) return Icons.functions_rounded;
  return Icons.menu_book_rounded;
}

/// 根据训练部位返回专属颜色与图标
({IconData icon, Color color, String emoji}) categoryVisual(String cat) {
  switch (cat) {
    case '胸':
      return (icon: Icons.shield_rounded, color: const Color(0xFFEF5350), emoji: '🔥');
    case '背':
      return (icon: Icons.view_stream_rounded, color: const Color(0xFF42A5F5), emoji: '🪽');
    case '腿':
      return (icon: Icons.directions_run_rounded, color: const Color(0xFFAB47BC), emoji: '🦵');
    case '肩':
      return (icon: Icons.accessibility_new_rounded, color: const Color(0xFFFFA726), emoji: '💪');
    case '手臂':
      return (icon: Icons.fitness_center_rounded, color: const Color(0xFF26A69A), emoji: '🦾');
    case '核心':
      return (icon: Icons.grid_view_rounded, color: const Color(0xFF66BB6A), emoji: '⚡');
    case '有氧':
      return (icon: Icons.favorite_rounded, color: const Color(0xFFEC407A), emoji: '🏃');
    default:
      return (icon: Icons.sports_gymnastics_rounded, color: const Color(0xFF5C6BC0), emoji: '🏋️');
  }
}

class L10nHelper {
  L10nHelper._();

  static const cardioDefaultType = '慢跑';
  static const cardioOtherCategory = '其他';

  static bool isCardioCategory(String rawCat) => rawCat == '有氧';

  static String weekdayLabel(BuildContext context, int weekday) {
    final l = context.l10n;
    switch (weekday) {
      case 1:
        return l.weekdayMon;
      case 2:
        return l.weekdayTue;
      case 3:
        return l.weekdayWed;
      case 4:
        return l.weekdayThu;
      case 5:
        return l.weekdayFri;
      case 6:
        return l.weekdaySat;
      default:
        return l.weekdaySun;
    }
  }

  static String mealTypeLabel(BuildContext context, int mealType) {
    final l = context.l10n;
    switch (mealType) {
      case 0:
        return l.mealBreakfast;
      case 1:
        return l.mealLunch;
      case 2:
        return l.mealDinner;
      default:
        return l.mealSnack;
    }
  }

  static String weekTypeLabel(BuildContext context, int weekType) {
    final l = context.l10n;
    switch (weekType) {
      case 1:
        return l.scheduleWeekOdd;
      case 2:
        return l.scheduleWeekEven;
      default:
        return l.scheduleWeekEvery;
    }
  }

  static String friendlyDateL10n(BuildContext context, String date) {
    final l = context.l10n;
    final d = parseDate(date);
    final now = dateOnly(DateTime.now());
    final diff = now.difference(d).inDays;
    if (diff == 0) return l.commonToday;
    if (diff == 1) return l.commonYesterday;
    if (diff == -1) return l.commonTomorrow;
    final wd = weekdayLabel(context, d.weekday);
    if (context.isEnLocale) {
      final y = d.year == now.year ? '' : '${d.year}/';
      return '$y${d.month}/${d.day} $wd';
    }
    final y = d.year == now.year ? '' : '${d.year}/';
    return '$y${d.month}/${d.day} $wd';
  }

  static String exerciseCategoryLabel(BuildContext context, String rawCat) {
    final l = context.l10n;
    switch (rawCat) {
      case '胸':
        return l.catChest;
      case '背':
        return l.catBack;
      case '腿':
        return l.catLegs;
      case '肩':
        return l.catShoulders;
      case '手臂':
        return l.catArms;
      case '核心':
        return l.catCore;
      case '有氧':
        return l.catCardio;
      default:
        return l.catOther;
    }
  }

  static const _seedExerciseEnMap = <String, String>{
    '杠铃卧推': 'Barbell Bench Press',
    '哑铃卧推': 'Dumbbell Bench Press',
    '上斜杠铃卧推': 'Incline Barbell Bench Press',
    '上斜哑铃卧推': 'Incline Dumbbell Press',
    '哑铃飞鸟': 'Dumbbell Fly',
    '龙门架夹胸': 'Cable Crossover',
    '器械推胸': 'Machine Chest Press',
    '双杠臂屈伸': 'Parallel Bar Dip',
    '俯卧撑': 'Push-up',
    '硬拉': 'Deadlift',
    '引体向上': 'Pull-up',
    '高位下拉': 'Lat Pulldown',
    '杠铃划船': 'Barbell Row',
    '哑铃单臂划船': 'One-Arm Dumbbell Row',
    '坐姿划船': 'Seated Cable Row',
    'T杠划船': 'T-Bar Row',
    '直臂下压': 'Straight-Arm Pulldown',
    '杠铃深蹲': 'Barbell Squat',
    '前蹲': 'Front Squat',
    '腿举': 'Leg Press',
    '罗马尼亚硬拉': 'Romanian Deadlift (RDL)',
    '保加利亚分腿蹲': 'Bulgarian Split Squat',
    '箭步蹲': 'Walking Lunge',
    '腿屈伸': 'Leg Extension',
    '腿弯举': 'Leg Curl',
    '提踵': 'Calf Raise',
    '臀推': 'Hip Thrust',
    '杠铃推举': 'Overhead Barbell Press',
    '哑铃推举': 'Seated Dumbbell Press',
    '哑铃侧平举': 'Lateral Raise',
    '龙门架侧平举': 'Cable Lateral Raise',
    '俯身飞鸟': 'Rear Delt Fly',
    '面拉': 'Face Pull',
    '器械推肩': 'Machine Shoulder Press',
    '杠铃弯举': 'Barbell Curl',
    '哑铃弯举': 'Dumbbell Curl',
    '锤式弯举': 'Hammer Curl',
    '绳索下压': 'Triceps Rope Pushdown',
    '仰卧臂屈伸': 'Skull Crusher',
    '过头臂屈伸': 'Overhead Triceps Extension',
    '平板支撑': 'Plank',
    '卷腹': 'Crunch',
    '悬垂举腿': 'Hanging Leg Raise',
    '健腹轮': 'Ab Wheel Rollout',
    '俄罗斯转体': 'Russian Twist',
    '跑步': 'Treadmill Run',
    '椭圆机': 'Elliptical',
    '动感单车': 'Spin Bike',
    '跳绳': 'Jump Rope',
    '爬楼梯机': 'StairMaster',
  };

  static String exerciseDisplayName(BuildContext context, String rawName) {
    if (!context.isEnLocale) return rawName;
    return _seedExerciseEnMap[rawName] ?? rawName;
  }

  static String cardioTypeLabel(BuildContext context, String rawType) {
    final l = context.l10n;
    switch (rawType) {
      case '走路':
        return l.cardioTypeWalk;
      case '快走':
        return l.cardioTypeBriskWalk;
      case '慢跑':
        return l.cardioTypeJog;
      case '中速跑':
        return l.cardioTypeRun;
      case '骑行':
        return l.cardioTypeCycle;
      case '游泳':
        return l.cardioTypeSwim;
      case '跳绳':
        return l.cardioTypeJumpRope;
      default:
        return l.cardioTypeOther;
    }
  }

  static String goalLabel(BuildContext context, String key) {
    final l = context.l10n;
    switch (key) {
      case 'lose':
        return l.goalLose;
      case 'gain':
        return l.goalGain;
      case 'fitness':
        return l.goalFitness;
      default:
        return l.goalMaintain;
    }
  }

  static String activityLabel(BuildContext context, double key) {
    final l = context.l10n;
    if (key <= 1.25) return l.actSedentary;
    if (key <= 1.45) return l.actLight;
    if (key <= 1.65) return l.actModerate;
    if (key <= 1.8) return l.actHigh;
    return l.actExtreme;
  }

  static String experienceLabel(BuildContext context, String key) {
    final l = context.l10n;
    switch (key) {
      case 'none':
        return l.expNone;
      case 'intermediate':
        return l.expIntermediate;
      case 'advanced':
        return l.expAdvanced;
      default:
        return l.expBeginner;
    }
  }

  static String equipmentLabel(BuildContext context, String key) {
    final l = context.l10n;
    switch (key) {
      case 'bodyweight':
        return l.equipBodyweight;
      case 'dumbbell':
        return l.equipDumbbell;
      case 'barbell':
        return l.equipBarbell;
      default:
        return l.equipGym;
    }
  }

  static String bmiStatusLabel(BuildContext context, double bmi) {
    final l = context.l10n;
    if (bmi < 18.5) return l.bmiUnderweight;
    if (bmi < 24) return l.bmiNormal;
    if (bmi < 28) return l.bmiOverweight;
    return l.bmiObese;
  }

  static String weatherConditionLabel(BuildContext context, int weatherCode) {
    final l = context.l10n;
    if (weatherCode == 0) return l.weatherClear;
    if (weatherCode <= 3) return l.weatherCloudy;
    if (weatherCode == 45 || weatherCode == 48) return l.weatherFoggy;
    if (weatherCode >= 51 && weatherCode <= 67) return l.weatherRainy;
    if (weatherCode >= 71 && weatherCode <= 77) return l.weatherSnowy;
    if (weatherCode >= 80 && weatherCode <= 82) return l.weatherShowers;
    if (weatherCode >= 95) return l.weatherThunderstorm;
    return l.weatherCloudy;
  }

  static String weatherShortTipLabel(BuildContext context, WeatherInfo w) {
    final l = context.l10n;
    if (w.isRainy) return l.weatherTipRain;
    if (w.temperature >= 32) return l.weatherTipHot;
    return l.weatherTipGreat;
  }

  static String weatherCompactSubLabel(BuildContext context, WeatherInfo w) {
    return context.l10n.weatherCompactSub(
      fmtNum(w.minTemp),
      fmtNum(w.maxTemp),
      fmtNum(w.precipProb),
      weatherShortTipLabel(context, w),
    );
  }

  static String weatherPresetLabel(BuildContext context, WeatherCityPreset p) {
    return context.isEnLocale ? p.city : p.label;
  }

  static String busStopDisplayName(BuildContext context, String rawName) {
    if (!context.isEnLocale) return rawName;
    return rawName
        .replaceAll('（到校）', ' (Campus)')
        .replaceAll('（发车）', ' (Depart)')
        .replaceAll('（终点）', ' (Terminal)');
  }

  static String busDirectionSummary(
    BuildContext context, {
    required String rawDirection,
    required String nextTime,
    required int minutesUntil,
    required bool isWeekend,
  }) {
    final l = context.l10n;
    if (isWeekend || rawDirection.contains('周末')) {
      return l.busHomeWeekend;
    }
    if (minutesUntil < 0 || rawDirection.contains('已结束')) {
      return l.busHomeEndedToday(nextTime);
    }
    final isInbound = rawDirection.toLowerCase().contains('inbound') ||
        rawDirection.contains('回程') ||
        rawDirection.toLowerCase().contains('drop');
    final dirLabel = isInbound ? l.busInboundSegment : l.busOutboundSegment;
    return l.busHomeNextCountdown(dirLabel, nextTime, minutesUntil);
  }

  static String cleanBusStopName(String s) =>
      s.replaceAll('（到校）', '').replaceAll('（发车）', '').replaceAll('（终点）', '').trim();

  static List<(String name, List<String> times)> parseStopLines(String raw) {
    final out = <(String, List<String>)>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      var idx = t.indexOf(':');
      if (idx <= 0) idx = t.indexOf('：');
      if (idx <= 0) continue;
      final name = t.substring(0, idx).trim();
      final times = t
          .substring(idx + 1)
          .split(RegExp(r'[,，\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      out.add((name, times));
    }
    return out;
  }

  static bool isWorkoutPlanRequest(String text) {
    final lower = text.toLowerCase();
    return text.contains('训练计划') ||
        text.contains('计划') ||
        lower.contains('workout plan') ||
        lower.contains('split') ||
        lower.contains('program');
  }

  static const planSchemaPromptInstruction =
      '\nWhen the user asks for a workout plan, write your explanation first, and at the very end of your reply wrap the structured plan JSON strictly inside <<<PLAN_JSON>>> and <<<END_PLAN>>> markers (do NOT use ```json markdown fences for the plan). Exact format:\n'
      '<<<PLAN_JSON>>>\n'
      '{"plan_name":"...","days":[{"day":"...","focus":"...","exercises":[{"name":"...","sets":4,"reps":"8-10","weight_hint":"..."}]}]}\n'
      '<<<END_PLAN>>>';
}
