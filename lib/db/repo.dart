import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../models/run_models.dart';
import '../services/academic_calendar_service.dart';
import '../services/battery_probe_service.dart';
import '../services/reminder_service.dart';
import '../services/widget_service.dart';
import '../utils/date_utils.dart';
import 'database.dart';

/// 所有数据库读写集中在这里。页面只调用 Repo，不直接写 SQL。
class Repo {
  Repo._();

  /// 全局数据变更版本号（训练/有氧/饮食/身体数据写库后自增，供饮食页/首页即时刷新）
  static final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);

  static void notifyDataChanged() {
    dataVersion.value++;
  }

  static Future<Database> get _db => AppDatabase.instance.db;

  // ---------------- kv ----------------
  static Future<String?> getKv(String key) async {
    final rows = await (await _db).query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<void> setKv(String key, String value) async {
    BatteryProbeService.instance.recordDbWrite();
    await (await _db).insert('kv', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 供耗电探针自身持久化使用，不计入业务写库次数
  static Future<void> setKvSilent(String key, String value) async {
    await (await _db).insert('kv', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Profile> getProfile() async {
    final s = await getKv('profile');
    if (s == null) return Profile();
    try {
      return Profile.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return Profile();
    }
  }

  static Future<bool> hasProfile() async => (await getKv('profile')) != null;

  static Future<void> saveProfile(Profile p) => setKv('profile', jsonEncode(p.toJson()));

  // ---------------- 课表 ----------------
  static Future<List<Course>> getCourses() async {
    final rows = await (await _db).query('courses', orderBy: 'weekday, start_section');
    return rows.map(Course.fromMap).toList();
  }

  static Future<bool> hasCourseSeedPrompted() async =>
      (await getKv('course_seed_prompted')) == '1';

  static Future<void> setCourseSeedPrompted() => setKv('course_seed_prompted', '1');

  static Future<int> saveCourse(Course c) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    final int res;
    if (c.id == null) {
      res = await db.insert('courses', c.toMap()..remove('id'));
    } else {
      await db.update('courses', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
      res = c.id!;
    }
    await setCourseSeedPrompted();
    notifyDataChanged();
    WidgetService.sync(force: true);
    ReminderService.syncAlarms();
    return res;
  }

  /// 一次保存多节课程（例如表单多选周一/三/五同时添加）
  static Future<void> saveCourses(List<Course> courses) async {
    if (courses.isEmpty) return;
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    await db.transaction((txn) async {
      for (final c in courses) {
        await txn.insert('courses', c.toMap()..remove('id'));
      }
    });
    await setCourseSeedPrompted();
    notifyDataChanged();
    WidgetService.sync(force: true);
    ReminderService.syncAlarms();
  }

  static Future<void> deleteCourse(int id) async {
    BatteryProbeService.instance.recordDbWrite();
    await (await _db).delete('courses', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
    WidgetService.sync(force: true);
    ReminderService.syncAlarms();
  }

  /// 清空所有课程并立即取消对应上课提醒闹钟（返回被删除的课程数量）
  static Future<int> clearAllCourses() async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    final deleted = await db.delete('courses');
    await setCourseSeedPrompted();
    await ReminderService.syncAlarms();
    notifyDataChanged();
    WidgetService.sync(force: true);
    return deleted;
  }

  /// 将内置 BUV 示例课表复制到数据库并标记 source = 'builtin'
  static Future<int> importBuiltinSampleCourses({bool replaceAll = false}) async {
    final samples = AppDatabase.defaultScheduleCourses
        .map((m) => Course.fromMap({...m, 'source': Course.sourceBuiltin}))
        .toList();
    await importCourses(samples, replaceAll: replaceAll);
    return samples.length;
  }

  static Future<void> importCourses(List<Course> courses, {bool replaceAll = false}) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete('courses');
      }
      for (final c in courses) {
        await txn.insert('courses', c.toMap()..remove('id'));
      }
    });
    await setCourseSeedPrompted();
    notifyDataChanged();
    WidgetService.sync(force: true);
    ReminderService.syncAlarms();
  }

  /// 学期第一周的周一日期（优先用户学期设置，其次自动从 academic_calendar.json 对应学期读取）
  static Future<DateTime> getSemesterStart() async {
    final term = await AcademicCalendarService.getActiveTerm();
    return term.week1Start;
  }

  static Future<void> setSemesterStart(DateTime d) =>
      setKv('semester_start', fmtDate(mondayOf(d)));

  static Future<int> getSectionsPerDay() async =>
      int.tryParse(await getKv('sections_per_day') ?? '') ?? 12;

  static Future<void> setSectionsPerDay(int n) => setKv('sections_per_day', '$n');

  // ---------------- 饮食 ----------------
  static Future<List<Meal>> getMeals(String date) async {
    final rows = await (await _db)
        .query('meals', where: 'date = ?', whereArgs: [date], orderBy: 'meal_type, created_at');
    return rows.map(Meal.fromMap).toList();
  }

  static Future<List<Meal>> getMealsBetween(String from, String to) async {
    final rows = await (await _db).query('meals',
        where: 'date >= ? AND date <= ?', whereArgs: [from, to], orderBy: 'date, meal_type');
    return rows.map(Meal.fromMap).toList();
  }

  static Future<int> saveMeal(Meal m) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    final int res;
    if (m.id == null) {
      res = await db.insert('meals', m.toMap()..remove('id'));
    } else {
      await db.update('meals', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
      res = m.id!;
    }
    WidgetService.sync(force: true);
    return res;
  }

  static Future<void> deleteMeal(int id) async {
    BatteryProbeService.instance.recordDbWrite();
    await (await _db).delete('meals', where: 'id = ?', whereArgs: [id]);
    WidgetService.sync(force: true);
  }

  // ---------------- 身体数据 ----------------
  static Future<List<BodyRecord>> getBodyRecords({int? limit}) async {
    final rows = await (await _db).query('body_records', orderBy: 'date DESC', limit: limit);
    return rows.map(BodyRecord.fromMap).toList();
  }

  static Future<BodyRecord?> latestBodyRecordWithWeight() async {
    final rows = await (await _db).query('body_records',
        where: 'weight IS NOT NULL', orderBy: 'date DESC', limit: 1);
    return rows.isEmpty ? null : BodyRecord.fromMap(rows.first);
  }

  /// 同一天只保留一条记录（覆盖）
  static Future<void> saveBodyRecord(BodyRecord r) async {
    BatteryProbeService.instance.recordDbWrite();
    r.date = dateOnlyStr(r.date);
    await (await _db).insert('body_records', r.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyDataChanged();
  }

  static Future<void> deleteBodyRecord(int id) async {
    BatteryProbeService.instance.recordDbWrite();
    await (await _db).delete('body_records', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  // ---------------- 动作库 ----------------
  static Future<List<Exercise>> getExercises() async {
    final rows = await (await _db).query('exercises', orderBy: 'category, is_custom, id');
    return rows.map(Exercise.fromMap).toList();
  }

  static Future<int> addExercise(Exercise e) async {
    BatteryProbeService.instance.recordDbWrite();
    return (await _db).insert('exercises', e.toMap()..remove('id'));
  }

  static Future<void> deleteExercise(int id) async {
    BatteryProbeService.instance.recordDbWrite();
    await (await _db).delete('exercises', where: 'id = ? AND is_custom = 1', whereArgs: [id]);
  }

  // ---------------- 训练 ----------------
  static Future<int> createWorkout(Workout w) async {
    BatteryProbeService.instance.recordDbWrite();
    w.date = dateOnlyStr(w.date);
    final id = await (await _db).insert('workouts', w.toMap()..remove('id'));
    notifyDataChanged();
    WidgetService.sync(force: true);
    return id;
  }

  static Future<void> updateWorkout(Workout w) async {
    BatteryProbeService.instance.recordDbWrite();
    w.date = dateOnlyStr(w.date);
    await (await _db).update('workouts', w.toMap(), where: 'id = ?', whereArgs: [w.id]);
    notifyDataChanged();
    WidgetService.sync(force: true);
  }

  static Future<void> deleteWorkout(int id) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('workout_sets', where: 'workout_id = ?', whereArgs: [id]);
      await txn.delete('workouts', where: 'id = ?', whereArgs: [id]);
    });
    notifyDataChanged();
    WidgetService.sync(force: true);
  }

  static Future<List<Workout>> getWorkouts({int? limit, String? from, String? date}) async {
    String? where;
    List<Object?>? args;
    if (date != null) {
      where = 'substr(date, 1, 10) = ?';
      args = [dateOnlyStr(date)];
    } else if (from != null) {
      where = 'substr(date, 1, 10) >= ?';
      args = [dateOnlyStr(from)];
    }
    final rows = await (await _db).query(
      'workouts',
      where: where,
      whereArgs: args,
      orderBy: 'start_time DESC',
      limit: limit,
    );
    return rows.map(Workout.fromMap).toList();
  }

  static Future<Workout?> getWorkout(int id) async {
    final rows = await (await _db).query('workouts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Workout.fromMap(rows.first);
  }

  /// 查询最近一条尚未结束的训练会话（end_time IS NULL），用于中断恢复与冷启动续练
  static Future<Workout?> getInProgressWorkout() async {
    final rows = await (await _db).query(
      'workouts',
      where: 'end_time IS NULL',
      orderBy: 'start_time DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Workout.fromMap(rows.first);
  }

  /// 查询近 [days] 天内去重后的常用食物，供快速记饮食一键填入
  static Future<List<Meal>> getRecentUniqueMeals({int days = 7, int limit = 8}) async {
    final fromDate = fmtDate(DateTime.now().subtract(Duration(days: days)));
    final rows = await (await _db).query(
      'meals',
      where: 'date >= ?',
      whereArgs: [fromDate],
      orderBy: 'created_at DESC',
      limit: 60,
    );
    final seen = <String>{};
    final out = <Meal>[];
    for (final r in rows) {
      final m = Meal.fromMap(r);
      final key = m.name.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(m);
      if (out.length >= limit) break;
    }
    return out;
  }

  static Future<List<WorkoutSet>> getSets(int workoutId) async {
    final rows = await (await _db).query('workout_sets',
        where: 'workout_id = ?', whereArgs: [workoutId], orderBy: 'id');
    return rows.map(WorkoutSet.fromMap).toList();
  }

  /// 用整组替换某次训练的所有组（编辑页保存时调用）
  static Future<void> replaceSets(int workoutId, List<WorkoutSet> sets) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('workout_sets', where: 'workout_id = ?', whereArgs: [workoutId]);
      for (final s in sets) {
        s.workoutId = workoutId;
        await txn.insert('workout_sets', s.toMap()..remove('id'));
      }
    });
    notifyDataChanged();
    WidgetService.sync(force: true);
  }

  /// 某个动作在 [excludeWorkoutId] 之外最近一次训练的所有组
  static Future<List<WorkoutSet>> lastSetsForExercise(int exerciseId, {int? excludeWorkoutId}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT s.workout_id FROM workout_sets s
      JOIN workouts w ON w.id = s.workout_id
      WHERE s.exercise_id = ? ${excludeWorkoutId != null ? 'AND s.workout_id != ?' : ''}
      ORDER BY w.start_time DESC LIMIT 1
    ''', [exerciseId, if (excludeWorkoutId != null) excludeWorkoutId]);
    if (rows.isEmpty) return [];
    final wid = rows.first['workout_id'] as int;
    final sets = await db.query('workout_sets',
        where: 'workout_id = ? AND exercise_id = ?', whereArgs: [wid, exerciseId], orderBy: 'id');
    return sets.map(WorkoutSet.fromMap).toList();
  }

  // ---------------- 独立有氧记录 ----------------
  static Future<List<CardioRecord>> getCardioRecords({String? date, String? from, int? limit}) async {
    String? where;
    List<Object?>? args;
    if (date != null) {
      where = 'substr(date, 1, 10) = ?';
      args = [dateOnlyStr(date)];
    } else if (from != null) {
      where = 'substr(date, 1, 10) >= ?';
      args = [dateOnlyStr(from)];
    }
    final rows = await (await _db).query(
      'cardio_records',
      where: where,
      whereArgs: args,
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(CardioRecord.fromMap).toList();
  }

  static Future<int> saveCardioRecord(CardioRecord r) async {
    BatteryProbeService.instance.recordDbWrite();
    r.date = dateOnlyStr(r.date);
    final db = await _db;
    final int res;
    if (r.id == null) {
      res = await db.insert('cardio_records', r.toMap()..remove('id'));
    } else {
      await db.update('cardio_records', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
      res = r.id!;
    }
    notifyDataChanged();
    WidgetService.sync(force: true);
    return res;
  }

  static Future<void> deleteCardioRecord(int id) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cardio_records',
        columns: ['source_run_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final sourceRunId =
          rows.isNotEmpty ? (rows.first['source_run_id'] as num?)?.toInt() : null;
      await txn.delete('cardio_records', where: 'id = ?', whereArgs: [id]);
      if (sourceRunId != null) {
        await txn.delete('run_segments', where: 'run_id = ?', whereArgs: [sourceRunId]);
        await txn.delete('runs', where: 'id = ?', whereArgs: [sourceRunId]);
      }
    });
    notifyDataChanged();
    WidgetService.sync(force: true);
  }

  // ---------------- 训练计划 & 首次问卷 ----------------
  static Future<TrainingPlan?> getTrainingPlan() async {
    final s = await getKv('active_training_plan');
    if (s == null || s.isEmpty) return null;
    try {
      return TrainingPlan.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTrainingPlan(TrainingPlan plan) async {
    await setKv('active_training_plan', jsonEncode(plan.toJson()));
    notifyDataChanged();
  }

  /// 清除当前活跃训练计划（不影响已完成的历史训练记录）
  static Future<void> clearTrainingPlan() async {
    await setKv('active_training_plan', '');
    notifyDataChanged();
  }

  static Future<bool> isOnboardingDone() async => (await getKv('onboarding_done')) == '1';

  static Future<void> setOnboardingDone() => setKv('onboarding_done', '1');

  /// 计算连续记录天数（饮食 / 训练 / 有氧 / 体重 任意一项有记录即算当天打卡）
  static Future<int> calculateStreak() async {
    final db = await _db;
    final activeDates = <String>{};
    for (final table in ['meals', 'workouts', 'cardio_records', 'body_records']) {
      final rows = await db.rawQuery('SELECT DISTINCT date FROM $table');
      for (final r in rows) {
        final d = r['date'] as String?;
        if (d != null) activeDates.add(d);
      }
    }
    if (activeDates.isEmpty) return 0;
    var check = dateOnly(DateTime.now());
    // 如果今天还没记，但昨天记了，从昨天开始算连续天数
    if (!activeDates.contains(fmtDate(check))) {
      final yesterday = check.subtract(const Duration(days: 1));
      if (!activeDates.contains(fmtDate(yesterday))) return 0;
      check = yesterday;
    }
    var streak = 0;
    while (activeDates.contains(fmtDate(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 按名称查找或自动创建动作（供训练计划一键开练使用）
  static Future<Exercise> findOrCreateExercise(String name, {String defaultCategory = '其他'}) async {
    final all = await getExercises();
    for (final e in all) {
      if (e.name.toLowerCase() == name.trim().toLowerCase() ||
          e.name.contains(name.trim()) ||
          name.trim().contains(e.name)) {
        return e;
      }
    }
    final ex = Exercise(name: name.trim(), category: defaultCategory, isCustom: true);
    ex.id = await addExercise(ex);
    return ex;
  }

  // ---------------- 跑步（runs + run_segments + 双写 cardio_records）----------------
  /// 纯辅助函数：根据 RunRecord 构造与 runs 数值完全一致的关联 CardioRecord（不重算热量）
  static CardioRecord buildLinkedCardioForRun(RunRecord run, {required int runId}) {
    return CardioRecord(
      date: dateOnlyStr(run.date),
      type: CardioType.run,
      durationMinutes: run.durationSecs / 60.0,
      distanceKm: run.distanceM / 1000.0,
      calories: run.caloriesKcal.toDouble(),
      sourceRunId: runId,
      createdAt: run.endTime ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<int> saveRun(
    RunRecord run, {
    List<RunSegmentRecord> segments = const [],
  }) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    final runId = await db.transaction<int>((txn) async {
      final int id;
      if (run.id == null) {
        id = await txn.insert('runs', run.toMap()..remove('id'));
      } else {
        await txn.update('runs', run.toMap(), where: 'id = ?', whereArgs: [run.id]);
        id = run.id!;
        await txn.delete('run_segments', where: 'run_id = ?', whereArgs: [id]);
      }
      for (final seg in segments) {
        final m = seg.toMap()..remove('id');
        m['run_id'] = id;
        await txn.insert('run_segments', m);
      }
      // 双写关联有氧记录：type='running'，直接复用 runs 数值（绝不各算各的），并携带 source_run_id
      await txn.delete('cardio_records', where: 'source_run_id = ?', whereArgs: [id]);
      final linkedCardio = buildLinkedCardioForRun(run, runId: id);
      await txn.insert('cardio_records', linkedCardio.toMap()..remove('id'));
      return id;
    });
    run.id = runId;
    notifyDataChanged();
    WidgetService.sync(force: true);
    return runId;
  }

  static Future<List<RunRecord>> getRuns({String? date, int? limit}) async {
    final normalized = date == null ? null : dateOnlyStr(date);
    final rows = await (await _db).query(
      'runs',
      where: normalized != null ? 'date = ?' : null,
      whereArgs: normalized != null ? [normalized] : null,
      orderBy: 'start_time DESC',
      limit: limit,
    );
    return rows.map(RunRecord.fromMap).toList();
  }

  static Future<RunRecord?> getRunById(int id) async {
    final rows = await (await _db).query('runs', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : RunRecord.fromMap(rows.first);
  }

  static Future<List<RunSegmentRecord>> getRunSegments(int runId) async {
    final rows = await (await _db).query(
      'run_segments',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 'seq ASC',
    );
    return rows.map(RunSegmentRecord.fromMap).toList();
  }

  static Future<void> deleteRun(int id) async {
    BatteryProbeService.instance.recordDbWrite();
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('run_segments', where: 'run_id = ?', whereArgs: [id]);
      await txn.delete('cardio_records', where: 'source_run_id = ?', whereArgs: [id]);
      await txn.delete('runs', where: 'id = ?', whereArgs: [id]);
    });
    notifyDataChanged();
    WidgetService.sync(force: true);
  }

  // ---------------- 聊天 ----------------
  static Future<List<ChatMessage>> getChatMessages() async {
    final rows = await (await _db).query('chat_messages', orderBy: 'id');
    return rows.map(ChatMessage.fromMap).toList();
  }

  static Future<int> addChatMessage(ChatMessage m) async {
    BatteryProbeService.instance.recordDbWrite();
    return (await _db).insert('chat_messages', m.toMap()..remove('id'));
  }

  static Future<void> clearChat() async {
    BatteryProbeService.instance.recordDbWrite();
    await (await _db).delete('chat_messages');
  }

  // ---------------- 导出 ----------------
  static Future<Map<String, dynamic>> exportAll() async {
    final db = await _db;
    final out = <String, dynamic>{
      'app': 'LifeLog',
      'exported_at': DateTime.now().toIso8601String(),
      'db_version': 7,
    };
    for (final t in [
      'kv',
      'courses',
      'meals',
      'body_records',
      'exercises',
      'workouts',
      'workout_sets',
      'cardio_records',
      'runs',
      'run_segments',
      'chat_messages'
    ]) {
      out[t] = await db.query(t);
    }
    return out;
  }
}
