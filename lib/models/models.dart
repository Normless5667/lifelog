// 所有数据模型。字段与 lib/db/database.dart 的表结构一一对应。

class Course {
  int? id;
  String name;
  String? teacher;
  String? location;
  int weekday; // 1=周一 ... 7=周日
  int startSection;
  int endSection;
  int startWeek;
  int endWeek;
  int weekType; // 0=每周 1=单周 2=双周
  int color;

  Course({
    this.id,
    required this.name,
    this.teacher,
    this.location,
    required this.weekday,
    required this.startSection,
    required this.endSection,
    this.startWeek = 1,
    this.endWeek = 16,
    this.weekType = 0,
    required this.color,
  });

  bool activeInWeek(int week) {
    if (week < startWeek || week > endWeek) return false;
    if (weekType == 1) return week.isOdd;
    if (weekType == 2) return week.isEven;
    return true;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'location': location,
        'weekday': weekday,
        'start_section': startSection,
        'end_section': endSection,
        'start_week': startWeek,
        'end_week': endWeek,
        'week_type': weekType,
        'color': color,
      };

  factory Course.fromMap(Map<String, Object?> m) => Course(
        id: m['id'] as int?,
        name: m['name'] as String,
        teacher: m['teacher'] as String?,
        location: m['location'] as String?,
        weekday: m['weekday'] as int,
        startSection: m['start_section'] as int,
        endSection: m['end_section'] as int,
        startWeek: m['start_week'] as int,
        endWeek: m['end_week'] as int,
        weekType: m['week_type'] as int,
        color: m['color'] as int,
      );
}

const mealTypeNames = ['早餐', '午餐', '晚餐', '加餐'];

class Meal {
  int? id;
  String date;
  int mealType;
  String name;
  String? amount;
  double calories;
  double protein;
  double carbs;
  double fat;
  String? photoPath;
  String? note;
  int createdAt;

  Meal({
    this.id,
    required this.date,
    required this.mealType,
    required this.name,
    this.amount,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.photoPath,
    this.note,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'meal_type': mealType,
        'name': name,
        'amount': amount,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'photo_path': photoPath,
        'note': note,
        'created_at': createdAt,
      };

  factory Meal.fromMap(Map<String, Object?> m) => Meal(
        id: m['id'] as int?,
        date: m['date'] as String,
        mealType: m['meal_type'] as int,
        name: m['name'] as String,
        amount: m['amount'] as String?,
        calories: (m['calories'] as num).toDouble(),
        protein: (m['protein'] as num).toDouble(),
        carbs: (m['carbs'] as num).toDouble(),
        fat: (m['fat'] as num).toDouble(),
        photoPath: m['photo_path'] as String?,
        note: m['note'] as String?,
        createdAt: m['created_at'] as int,
      );
}

/// AI 识别出的一项食物（保存前可编辑）。
class FoodEstimate {
  String name;
  String amount;
  double calories;
  double protein;
  double carbs;
  double fat;

  FoodEstimate({
    required this.name,
    this.amount = '',
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(v);
      if (match != null) return double.parse(match.group(0)!);
    }
    return 0;
  }

  factory FoodEstimate.fromJson(Map<String, dynamic> j) => FoodEstimate(
        name: (j['name'] ?? '未知食物').toString(),
        amount: (j['amount'] ?? '').toString(),
        calories: _num(j['calories']),
        protein: _num(j['protein']),
        carbs: _num(j['carbs']),
        fat: _num(j['fat']),
      );
}

class BodyRecord {
  int? id;
  String date;
  double? weight;
  double? bodyFat;
  double? waist;

  BodyRecord({this.id, required this.date, this.weight, this.bodyFat, this.waist});

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'weight': weight,
        'body_fat': bodyFat,
        'waist': waist,
      };

  factory BodyRecord.fromMap(Map<String, Object?> m) => BodyRecord(
        id: m['id'] as int?,
        date: m['date'] as String,
        weight: (m['weight'] as num?)?.toDouble(),
        bodyFat: (m['body_fat'] as num?)?.toDouble(),
        waist: (m['waist'] as num?)?.toDouble(),
      );
}

class Exercise {
  int? id;
  String name;
  String category;
  bool isCustom;

  Exercise({this.id, required this.name, required this.category, this.isCustom = false});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'is_custom': isCustom ? 1 : 0,
      };

  factory Exercise.fromMap(Map<String, Object?> m) => Exercise(
        id: m['id'] as int?,
        name: m['name'] as String,
        category: m['category'] as String,
        isCustom: (m['is_custom'] as int) == 1,
      );
}

class Workout {
  int? id;
  String date;
  int startTime;
  int? endTime;
  String? note;

  Workout({this.id, required this.date, required this.startTime, this.endTime, this.note});

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'note': note,
      };

  factory Workout.fromMap(Map<String, Object?> m) => Workout(
        id: m['id'] as int?,
        date: m['date'] as String,
        startTime: m['start_time'] as int,
        endTime: m['end_time'] as int?,
        note: m['note'] as String?,
      );
}

class WorkoutSet {
  int? id;
  int workoutId;
  int exerciseId;
  int setIndex;
  double weight;
  int reps;
  bool isWarmup;

  WorkoutSet({
    this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.setIndex,
    this.weight = 0,
    this.reps = 0,
    this.isWarmup = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'set_index': setIndex,
        'weight': weight,
        'reps': reps,
        'is_warmup': isWarmup ? 1 : 0,
      };

  factory WorkoutSet.fromMap(Map<String, Object?> m) => WorkoutSet(
        id: m['id'] as int?,
        workoutId: m['workout_id'] as int,
        exerciseId: m['exercise_id'] as int,
        setIndex: m['set_index'] as int,
        weight: (m['weight'] as num).toDouble(),
        reps: m['reps'] as int,
        isWarmup: (m['is_warmup'] as int) == 1,
      );
}

class ChatMessage {
  int? id;
  String role; // user / assistant
  String content;
  int createdAt;

  ChatMessage({this.id, required this.role, required this.content, int? createdAt})
      : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toMap() => {
        'id': id,
        'role': role,
        'content': content,
        'created_at': createdAt,
      };

  factory ChatMessage.fromMap(Map<String, Object?> m) => ChatMessage(
        id: m['id'] as int?,
        role: m['role'] as String,
        content: m['content'] as String,
        createdAt: m['created_at'] as int,
      );
}

/// 用户基础资料 + 首次使用问卷信息（存于 kv 表的 profile 键，JSON）。
class Profile {
  String gender; // male / female
  int age;
  double height; // cm
  double activity; // 活动系数 1.2 ~ 1.9
  String goal; // lose / maintain / gain / fitness
  double? targetWeight;
  String experience; // none / beginner / intermediate / advanced
  int weeklyDays; // 每周可训练天数 1~7
  int sessionMinutes; // 每次可训练时长（分钟）
  String equipment; // bodyweight / dumbbell / barbell / gym
  String injuries; // 伤病限制说明

  Profile({
    this.gender = 'male',
    this.age = 20,
    this.height = 170,
    this.activity = 1.375,
    this.goal = 'maintain',
    this.targetWeight,
    this.experience = 'beginner',
    this.weeklyDays = 3,
    this.sessionMinutes = 60,
    this.equipment = 'gym',
    this.injuries = '',
  });

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'age': age,
        'height': height,
        'activity': activity,
        'goal': goal,
        'targetWeight': targetWeight,
        'experience': experience,
        'weeklyDays': weeklyDays,
        'sessionMinutes': sessionMinutes,
        'equipment': equipment,
        'injuries': injuries,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        gender: j['gender'] ?? 'male',
        age: (j['age'] ?? 20) as int,
        height: ((j['height'] ?? 170) as num).toDouble(),
        activity: ((j['activity'] ?? 1.375) as num).toDouble(),
        goal: j['goal'] ?? 'maintain',
        targetWeight: (j['targetWeight'] as num?)?.toDouble(),
        experience: (j['experience'] ?? 'beginner').toString(),
        weeklyDays: (j['weeklyDays'] as num?)?.toInt() ?? 3,
        sessionMinutes: (j['sessionMinutes'] as num?)?.toInt() ?? 60,
        equipment: (j['equipment'] ?? 'gym').toString(),
        injuries: (j['injuries'] ?? '').toString(),
      );
}

/// 独立有氧运动记录（MET 消耗计算：kcal = MET × weightKg × hours）
class CardioRecord {
  int? id;
  String date;
  String type; // 走路 / 快走 / 慢跑 / 中速跑 / 骑行 / 游泳 / 跳绳 / 其他
  double durationMinutes;
  double? distanceKm;
  double calories;
  int createdAt;

  CardioRecord({
    this.id,
    required this.date,
    required this.type,
    required this.durationMinutes,
    this.distanceKm,
    required this.calories,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'type': type,
        'duration_minutes': durationMinutes,
        'distance_km': distanceKm,
        'calories': calories,
        'created_at': createdAt,
      };

  factory CardioRecord.fromMap(Map<String, Object?> m) => CardioRecord(
        id: m['id'] as int?,
        date: m['date'] as String,
        type: m['type'] as String,
        durationMinutes: (m['duration_minutes'] as num).toDouble(),
        distanceKm: (m['distance_km'] as num?)?.toDouble(),
        calories: (m['calories'] as num).toDouble(),
        createdAt: m['created_at'] as int,
      );
}

/// AI 生成并导入的结构化训练计划
class TrainingPlanExercise {
  String name;
  int sets;
  String reps;
  String weightHint;

  TrainingPlanExercise({
    required this.name,
    this.sets = 4,
    this.reps = '8-12',
    this.weightHint = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': sets,
        'reps': reps,
        'weight_hint': weightHint,
      };

  factory TrainingPlanExercise.fromJson(Map<String, dynamic> j) => TrainingPlanExercise(
        name: (j['name'] ?? '动作').toString(),
        sets: (j['sets'] is num) ? (j['sets'] as num).toInt() : (int.tryParse('${j['sets']}') ?? 4),
        reps: (j['reps'] ?? '8-12').toString(),
        weightHint: (j['weight_hint'] ?? '').toString(),
      );
}

class TrainingPlanDay {
  String day;
  String focus;
  List<TrainingPlanExercise> exercises;

  TrainingPlanDay({required this.day, required this.focus, required this.exercises});

  Map<String, dynamic> toJson() => {
        'day': day,
        'focus': focus,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  factory TrainingPlanDay.fromJson(Map<String, dynamic> j) => TrainingPlanDay(
        day: (j['day'] ?? '训练日').toString(),
        focus: (j['focus'] ?? '综合').toString(),
        exercises: ((j['exercises'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TrainingPlanExercise.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class TrainingPlan {
  String planName;
  List<TrainingPlanDay> days;

  TrainingPlan({required this.planName, required this.days});

  Map<String, dynamic> toJson() => {
        'plan_name': planName,
        'days': days.map((d) => d.toJson()).toList(),
      };

  factory TrainingPlan.fromJson(Map<String, dynamic> j) => TrainingPlan(
        planName: (j['plan_name'] ?? '我的训练计划').toString(),
        days: ((j['days'] as List?) ?? const [])
            .whereType<Map>()
            .map((d) => TrainingPlanDay.fromJson(Map<String, dynamic>.from(d)))
            .toList(),
      );
}
