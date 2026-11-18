import '../db/repo.dart';
import '../models/models.dart';
import '../utils/date_utils.dart';
import 'nutrition.dart';
import 'step_service.dart';
import 'weather_service.dart';

/// 为 AI 组装用户的个人数据上下文（作为 system prompt 的一部分）。
class ContextBuilder {
  ContextBuilder._();

  static Future<String> buildSystemPrompt() async {
    final buf = StringBuffer()
      ..writeln('你是用户的私人健康助手，精通营养学和力量训练。请用简体中文回答，语气友好、具体、可执行。')
      ..writeln('回答时结合下面的用户数据；数据不足时可以提醒用户补充记录。不要编造数据。')
      ..writeln('涉及疾病或伤病时提醒用户咨询医生。')
      ..writeln()
      ..writeln('今天是 ${today()}（${weekdayNames[DateTime.now().weekday - 1]}）。')
      ..writeln();

    final weather = await WeatherService.getWeather();
    if (weather != null) {
      buf.writeln('【今日天气】${weather.city}：${weather.summaryLine}');
      buf.writeln();
    }
    final stepState = await StepService.getTodaySteps();
    buf.writeln('【今日步数】已走 ${stepState.todaySteps} / 目标 ${stepState.goal} 步（折算消耗约 ${fmtNum(stepState.burnedKcal)} kcal）');
    buf.writeln();

    buf.writeln(await _profileSection());
    buf.writeln(await _dietSection());
    buf.writeln(await _workoutSection());
    buf.writeln(await _scheduleSection());
    return buf.toString();
  }

  static Future<String> _profileSection() async {
    final p = await Repo.getProfile();
    final records = await Repo.getBodyRecords(limit: 30);
    final latest = records.where((r) => r.weight != null).toList();
    final b = StringBuffer('【身体资料】\n');
    b.writeln('性别：${p.gender == 'female' ? '女' : '男'}，年龄：${p.age}，身高：${fmtNum(p.height)}cm，'
        '目标：${Nutrition.goals[p.goal]}，活动水平：${Nutrition.activityLevels[p.activity] ?? p.activity}');
    b.writeln('训练经验：${Nutrition.experiences[p.experience] ?? p.experience}，'
        '每周可练 ${p.weeklyDays} 天，每次约 ${p.sessionMinutes} 分钟，'
        '可用器械：${Nutrition.equipments[p.equipment] ?? p.equipment}'
        '${p.injuries.isNotEmpty ? '，伤病/限制：${p.injuries}' : ''}');
    if (p.targetWeight != null) b.writeln('目标体重：${fmtNum(p.targetWeight!, digits: 1)}kg');
    if (latest.isNotEmpty) {
      final w = latest.first.weight!;
      b.writeln('最新体重：${fmtNum(w, digits: 1)}kg（${latest.first.date}），'
          'BMI ${fmtNum(Nutrition.bmi(p.height, w), digits: 1)}，'
          'TDEE 约 ${fmtNum(Nutrition.tdee(p, w))}kcal，每日热量目标 ${fmtNum(Nutrition.calorieTarget(p, w))}kcal');
      final bf = records.firstWhere((r) => r.bodyFat != null, orElse: () => BodyRecord(date: ''));
      if (bf.bodyFat != null) b.writeln('体脂率：${fmtNum(bf.bodyFat!, digits: 1)}%（${bf.date}）');
      if (latest.length > 1) {
        b.writeln('近期体重记录：${latest.take(10).map((r) => '${r.date.substring(5)} ${fmtNum(r.weight!, digits: 1)}').join('，')}');
      }
    } else {
      b.writeln('（暂无体重记录）');
    }
    return b.toString();
  }

  static Future<String> _dietSection() async {
    final now = DateTime.now();
    final from = fmtDate(now.subtract(const Duration(days: 6)));
    final meals = await Repo.getMealsBetween(from, today());
    final b = StringBuffer('【近 7 天饮食】\n');
    if (meals.isEmpty) {
      b.writeln('（暂无饮食记录）');
      return b.toString();
    }
    final byDate = <String, List<Meal>>{};
    for (final m in meals) {
      byDate.putIfAbsent(m.date, () => []).add(m);
    }
    for (final e in byDate.entries) {
      double kcal = 0, pr = 0, c = 0, f = 0;
      for (final m in e.value) {
        kcal += m.calories;
        pr += m.protein;
        c += m.carbs;
        f += m.fat;
      }
      b.writeln('${e.key}：${fmtNum(kcal)}kcal，蛋白 ${fmtNum(pr)}g，碳水 ${fmtNum(c)}g，脂肪 ${fmtNum(f)}g');
      if (e.key == today()) {
        for (final m in e.value) {
          b.writeln('  - ${mealTypeNames[m.mealType]}：${m.name}${m.amount?.isNotEmpty == true ? '（${m.amount}）' : ''} ${fmtNum(m.calories)}kcal');
        }
      }
    }
    return b.toString();
  }

  static Future<String> _workoutSection() async {
    final from = fmtDate(DateTime.now().subtract(const Duration(days: 13)));
    final workouts = await Repo.getWorkouts(from: from);
    final b = StringBuffer('【近 14 天训练】\n');
    if (workouts.isEmpty) {
      b.writeln('（暂无训练记录）');
      return b.toString();
    }
    final exercises = {for (final e in await Repo.getExercises()) e.id: e};
    for (final w in workouts.reversed) {
      final sets = await Repo.getSets(w.id!);
      final byEx = <int, List<WorkoutSet>>{};
      for (final s in sets) {
        byEx.putIfAbsent(s.exerciseId, () => []).add(s);
      }
      final parts = byEx.entries.map((e) {
        final ex = exercises[e.key];
        final name = ex?.name ?? '未知动作';
        final isCardio = ex?.category == '有氧';
        final work = e.value.where((s) => !s.isWarmup).map((s) {
          if (isCardio) {
            return '${fmtNum(s.weight)}分钟${s.reps > 0 ? '/${s.reps}步' : ''}';
          }
          return '${fmtNum(s.weight, digits: 1)}kg×${s.reps}';
        }).join(' ');
        return '$name[$work]';
      });
      b.writeln('${w.date}：${parts.join('；')}');
    }
    final cardios = await Repo.getCardioRecords(from: from);
    if (cardios.isNotEmpty) {
      b.writeln('【近 14 天独立有氧】');
      for (final c in cardios.reversed) {
        b.writeln('${c.date}：${c.type} ${fmtNum(c.durationMinutes)}分钟'
            '${c.distanceKm != null ? ' ${fmtNum(c.distanceKm!, digits: 2)}km' : ''}'
            '（消耗约 ${fmtNum(c.calories)}kcal）');
      }
    }
    return b.toString();
  }

  static Future<String> _scheduleSection() async {
    final courses = await Repo.getCourses();
    if (courses.isEmpty) return '';
    final start = await Repo.getSemesterStart();
    final week = weekOfSemester(start, DateTime.now());
    final b = StringBuffer('【本周课表（第 $week 周）】\n');
    for (var d = 1; d <= 7; d++) {
      final cs = courses.where((c) => c.weekday == d && c.activeInWeek(week)).toList();
      if (cs.isEmpty) continue;
      b.writeln('${weekdayNames[d - 1]}：${cs.map((c) => '${c.name}(第${c.startSection}-${c.endSection}节)').join('，')}');
    }
    return b.toString();
  }
}
