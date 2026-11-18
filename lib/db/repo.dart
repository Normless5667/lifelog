import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../services/widget_service.dart';
import '../utils/date_utils.dart';
import 'database.dart';

/// 所有数据库读写集中在这里。页面只调用 Repo，不直接写 SQL。
class Repo {
  Repo._();

  static Future<Database> get _db => AppDatabase.instance.db;

  // ---------------- kv ----------------
  static Future<String?> getKv(String key) async {
    final rows = await (await _db).query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<void> setKv(String key, String value) async {
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

  static Future<int> saveCourse(Course c) async {
    final db = await _db;
    final int res;
    if (c.id == null) {
      res = await db.insert('courses', c.toMap()..remove('id'));
    } else {
      await db.update('courses', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
      res = c.id!;
    }
    WidgetService.sync(force: true);
    return res;
  }

  static Future<void> deleteCourse(int id) async {
    await (await _db).delete('courses', where: 'id = ?', whereArgs: [id]);
    WidgetService.sync(force: true);
  }

  static Future<void> importCourses(List<Course> courses, {bool replaceAll = false}) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete('courses');
      }
      for (final c in courses) {
        await txn.insert('courses', c.toMap()..remove('id'));
      }
    });
    WidgetService.sync(force: true);
  }

  /// 学期第一周的周一日期
  static Future<DateTime> getSemesterStart() async {
    final s = await getKv('semester_start');
    if (s != null) {
      final d = DateTime.tryParse(s);
      if (d != null) return d;
    }
    return mondayOf(DateTime.now());
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
    await (await _db).insert('body_records', r.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteBodyRecord(int id) async {
    await (await _db).delete('body_records', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- 动作库 ----------------
  static Future<List<Exercise>> getExercises() async {
    final rows = await (await _db).query('exercises', orderBy: 'category, is_custom, id');
    return rows.map(Exercise.fromMap).toList();
  }

  static Future<int> addExercise(Exercise e) async =>
      (await _db).insert('exercises', e.toMap()..remove('id'));

  static Future<void> deleteExercise(int id) async {
    await (await _db).delete('exercises', where: 'id = ? AND is_custom = 1', whereArgs: [id]);
  }

  // ---------------- 训练 ----------------
  static Future<int> createWorkout(Workout w) async {
    final id = await (await _db).insert('workouts', w.toMap()..remove('id'));
    WidgetService.sync(force: true);
    return id;
  }

  static Future<void> updateWorkout(Workout w) async {
    await (await _db).update('workouts', w.toMap(), where: 'id = ?', whereArgs: [w.id]);
    WidgetService.sync(force: true);
  }

  static Future<void> deleteWorkout(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('workout_sets', where: 'workout_id = ?', whereArgs: [id]);
      await txn.delete('workouts', where: 'id = ?', whereArgs: [id]);
    });
    WidgetService.sync(force: true);
  }

  static Future<List<Workout>> getWorkouts({int? limit, String? from}) async {
    final rows = await (await _db).query('workouts',
        where: from == null ? null : 'date >= ?',
        whereArgs: from == null ? null : [from],
        orderBy: 'start_time DESC',
        limit: limit);
    return rows.map(Workout.fromMap).toList();
  }

  static Future<Workout?> getWorkout(int id) async {
    final rows = await (await _db).query('workouts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Workout.fromMap(rows.first);
  }

  static Future<List<WorkoutSet>> getSets(int workoutId) async {
    final rows = await (await _db).query('workout_sets',
        where: 'workout_id = ?', whereArgs: [workoutId], orderBy: 'id');
    return rows.map(WorkoutSet.fromMap).toList();
  }

  /// 用整组替换某次训练的所有组（编辑页保存时调用）
  static Future<void> replaceSets(int workoutId, List<WorkoutSet> sets) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('workout_sets', where: 'workout_id = ?', whereArgs: [workoutId]);
      for (final s in sets) {
        s.workoutId = workoutId;
        await txn.insert('workout_sets', s.toMap()..remove('id'));
      }
    });
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
      where = 'date = ?';
      args = [date];
    } else if (from != null) {
      where = 'date >= ?';
      args = [from];
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
    final db = await _db;
    final int res;
    if (r.id == null) {
      res = await db.insert('cardio_records', r.toMap()..remove('id'));
    } else {
      await db.update('cardio_records', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
      res = r.id!;
    }
    WidgetService.sync(force: true);
    return res;
  }

  static Future<void> deleteCardioRecord(int id) async {
    await (await _db).delete('cardio_records', where: 'id = ?', whereArgs: [id]);
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

  static Future<void> saveTrainingPlan(TrainingPlan plan) =>
      setKv('active_training_plan', jsonEncode(plan.toJson()));

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

  // ---------------- 聊天 ----------------
  static Future<List<ChatMessage>> getChatMessages() async {
    final rows = await (await _db).query('chat_messages', orderBy: 'id');
    return rows.map(ChatMessage.fromMap).toList();
  }

  static Future<int> addChatMessage(ChatMessage m) async =>
      (await _db).insert('chat_messages', m.toMap()..remove('id'));

  static Future<void> clearChat() async {
    await (await _db).delete('chat_messages');
  }

  // ---------------- 导出 ----------------
  static Future<Map<String, dynamic>> exportAll() async {
    final db = await _db;
    final out = <String, dynamic>{
      'app': 'LifeLog',
      'exported_at': DateTime.now().toIso8601String(),
      'db_version': 3,
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
      'chat_messages'
    ]) {
      out[t] = await db.query(t);
    }
    return out;
  }
}
