import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 全局数据库单例。修改表结构时必须提升 [_dbVersion] 并在 [_onUpgrade] 写迁移。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'lifelog.db';
  static const _dbVersion = 3;

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final b = db.batch();
    b.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
    b.execute('''
      CREATE TABLE courses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        teacher TEXT,
        location TEXT,
        weekday INTEGER NOT NULL,
        start_section INTEGER NOT NULL,
        end_section INTEGER NOT NULL,
        start_week INTEGER NOT NULL DEFAULT 1,
        end_week INTEGER NOT NULL DEFAULT 16,
        week_type INTEGER NOT NULL DEFAULT 0,
        color INTEGER NOT NULL
      )''');
    b.execute('''
      CREATE TABLE meals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        meal_type INTEGER NOT NULL,
        name TEXT NOT NULL,
        amount TEXT,
        calories REAL NOT NULL DEFAULT 0,
        protein REAL NOT NULL DEFAULT 0,
        carbs REAL NOT NULL DEFAULT 0,
        fat REAL NOT NULL DEFAULT 0,
        photo_path TEXT,
        note TEXT,
        created_at INTEGER NOT NULL
      )''');
    b.execute('CREATE INDEX idx_meals_date ON meals(date)');
    b.execute('''
      CREATE TABLE body_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        weight REAL,
        body_fat REAL,
        waist REAL
      )''');
    b.execute('''
      CREATE TABLE exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('''
      CREATE TABLE workouts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        note TEXT
      )''');
    b.execute('''
      CREATE TABLE workout_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id INTEGER NOT NULL,
        exercise_id INTEGER NOT NULL,
        set_index INTEGER NOT NULL,
        weight REAL NOT NULL DEFAULT 0,
        reps INTEGER NOT NULL DEFAULT 0,
        is_warmup INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('CREATE INDEX idx_sets_workout ON workout_sets(workout_id)');
    b.execute('CREATE INDEX idx_sets_exercise ON workout_sets(exercise_id)');
    b.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    b.execute('''
      CREATE TABLE cardio_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        duration_minutes REAL NOT NULL DEFAULT 0,
        distance_km REAL,
        calories REAL NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    b.execute('CREATE INDEX idx_cardio_date ON cardio_records(date)');

    for (final entry in _seedExercises.entries) {
      for (final name in entry.value) {
        b.insert('exercises', {'name': name, 'category': entry.key, 'is_custom': 0});
      }
    }
    for (final c in defaultScheduleCourses) {
      b.insert('courses', c);
    }
    await b.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final existing = await db.query('courses', limit: 1);
      if (existing.isEmpty) {
        final b = db.batch();
        for (final c in defaultScheduleCourses) {
          b.insert('courses', c);
        }
        await b.commit(noResult: true);
      }
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cardio_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          type TEXT NOT NULL,
          duration_minutes REAL NOT NULL DEFAULT 0,
          distance_km REAL,
          calories REAL NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cardio_date ON cardio_records(date)');
    }
  }

  /// 用户真实课表（从 5 张 My Schedule 截图中提取，按每小节 30 分钟映射：1节=09:00-09:30 ... 12节=14:30-15:00）
  static const List<Map<String, Object?>> defaultScheduleCourses = [
    // Mon (weekday=1)
    {
      'name': 'Database Principles and Applications (09:00-10:30)',
      'teacher': 'Sasikumar Perumal',
      'location': 'E.3-8 Classroom',
      'weekday': 1,
      'start_section': 1,
      'end_section': 3,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFF26A69A,
    },
    {
      'name': 'Introduction to Machine Learning (10:30-12:00)',
      'teacher': 'Chong Zeng',
      'location': 'E.3-8 Classroom',
      'weekday': 1,
      'start_section': 4,
      'end_section': 6,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFF42A5F5,
    },
    // Tue (weekday=2)
    {
      'name': 'Database Principles and Applications (09:00-12:00)',
      'teacher': 'Sasikumar Perumal',
      'location': 'D.2-2 Digital Lab',
      'weekday': 2,
      'start_section': 1,
      'end_section': 6,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFF26A69A,
    },
    {
      'name': 'UX Design/SEM/1/1 (14:00-15:00)',
      'teacher': 'Long Hoang',
      'location': 'B.3-17~19 Learning Studio',
      'weekday': 2,
      'start_section': 11,
      'end_section': 12,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFFAB47BC,
    },
    // Wed (weekday=3)
    {
      'name': 'Introduction to Machine Learning (09:00-12:00)',
      'teacher': 'Chong Zeng',
      'location': 'D.2-2 Digital Lab',
      'weekday': 3,
      'start_section': 1,
      'end_section': 6,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFF42A5F5,
    },
    // Thu (weekday=4)
    {
      'name': 'Introduction to Machine Learning (09:00-10:30)',
      'teacher': 'Chong Zeng',
      'location': 'E.3-5 Classroom',
      'weekday': 4,
      'start_section': 1,
      'end_section': 3,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFF42A5F5,
    },
    {
      'name': 'UX Design/WKS/1/1 (12:00-15:00)',
      'teacher': 'Long Hoang',
      'location': 'D.2-2 Digital Lab',
      'weekday': 4,
      'start_section': 7,
      'end_section': 12,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFFAB47BC,
    },
    // Fri (weekday=5)
    {
      'name': 'Database Principles and Applications (09:00-10:30)',
      'teacher': 'Sasikumar Perumal',
      'location': 'E.2-4 Classroom',
      'weekday': 5,
      'start_section': 1,
      'end_section': 3,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFF26A69A,
    },
    {
      'name': 'UX Design/SEM/2/1 (13:00-15:00)',
      'teacher': 'Long Hoang',
      'location': 'B.2-8 Learning Studio',
      'weekday': 5,
      'start_section': 9,
      'end_section': 12,
      'start_week': 1,
      'end_week': 20,
      'week_type': 0,
      'color': 0xFFAB47BC,
    },
  ];

  static const exerciseCategories = ['胸', '背', '腿', '肩', '手臂', '核心', '有氧', '其他'];

  static const Map<String, List<String>> _seedExercises = {
    '胸': ['杠铃卧推', '哑铃卧推', '上斜杠铃卧推', '上斜哑铃卧推', '哑铃飞鸟', '龙门架夹胸', '器械推胸', '双杠臂屈伸', '俯卧撑'],
    '背': ['硬拉', '引体向上', '高位下拉', '杠铃划船', '哑铃单臂划船', '坐姿划船', 'T杠划船', '直臂下压'],
    '腿': ['杠铃深蹲', '前蹲', '腿举', '罗马尼亚硬拉', '保加利亚分腿蹲', '箭步蹲', '腿屈伸', '腿弯举', '提踵', '臀推'],
    '肩': ['杠铃推举', '哑铃推举', '哑铃侧平举', '龙门架侧平举', '俯身飞鸟', '面拉', '器械推肩'],
    '手臂': ['杠铃弯举', '哑铃弯举', '锤式弯举', '绳索下压', '仰卧臂屈伸', '过头臂屈伸'],
    '核心': ['平板支撑', '卷腹', '悬垂举腿', '健腹轮', '俄罗斯转体'],
    '有氧': ['跑步', '椭圆机', '动感单车', '跳绳', '爬楼梯机'],
  };
}
