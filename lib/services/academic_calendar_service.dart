import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../db/repo.dart';
import '../utils/date_utils.dart';

/// 校历中单个特殊日期的置信度
enum CalendarHolidayConfidence { high, low }

/// 用户对低置信度（confidence=low）校历红格子的手动确认状态
enum LowConfidenceOverride {
  /// 默认：中性「非教学日」标记，不按假期处理、不写「假期」二字
  neutral,

  /// 用户手动确认为假期（隐藏课程并跳过提醒）
  holiday,

  /// 用户确认为正常教学日（不显示标记）
  normal,
}

/// 校历中的单日标记条目
class CalendarHolidayEntry {
  final String date; // yyyy-MM-dd
  final String name;
  final String nameZh;
  final String source;
  final CalendarHolidayConfidence confidence;

  const CalendarHolidayEntry({
    required this.date,
    required this.name,
    required this.nameZh,
    this.source = 'calendar',
    this.confidence = CalendarHolidayConfidence.high,
  });

  String localizedName({required bool isEn}) {
    if (isEn) return name.isNotEmpty ? name : nameZh;
    return nameZh.isNotEmpty ? nameZh : name;
  }

  factory CalendarHolidayEntry.fromJson(Map<String, dynamic> j) {
    final confStr = (j['confidence'] ?? 'high').toString().trim().toLowerCase();
    return CalendarHolidayEntry(
      date: dateOnlyStr((j['date'] ?? '').toString()),
      name: (j['name'] ?? j['en'] ?? '').toString().trim(),
      nameZh: (j['nameZh'] ?? j['zh'] ?? j['name'] ?? '').toString().trim(),
      source: (j['source'] ?? 'calendar').toString().trim(),
      confidence: confStr == 'low'
          ? CalendarHolidayConfidence.low
          : CalendarHolidayConfidence.high,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'name': name,
        'nameZh': nameZh,
        'source': source,
        'confidence': confidence == CalendarHolidayConfidence.low ? 'low' : 'high',
      };
}

/// 单周在学期中的周期状态
enum WeekPeriodStatus {
  /// 第 1 周之前（学期未开始）
  beforeSemester,

  /// 第 0 周迎新周（仍属于第 1 周之前）
  orientation,

  /// 正常教学周（第 1 ~ totalWeeks 周）
  teaching,

  /// 考试周（Assessment Period）
  assessment,

  /// 教学周与考试周之后（学期已结束）
  afterSemester,
}

/// 单周状态与起止日期信息
class WeekStatusInfo {
  final AcademicTerm term;
  final int week;
  final DateTime startDate;
  final DateTime endDate;
  final WeekPeriodStatus periodStatus;

  const WeekStatusInfo({
    required this.term,
    required this.week,
    required this.startDate,
    required this.endDate,
    required this.periodStatus,
  });

  bool get isBeforeSemester =>
      periodStatus == WeekPeriodStatus.beforeSemester ||
      periodStatus == WeekPeriodStatus.orientation;

  bool get isAfterTeaching =>
      periodStatus == WeekPeriodStatus.assessment ||
      periodStatus == WeekPeriodStatus.afterSemester;
}

/// 单个学期定义（对应 academic_calendar.json 中 terms[] 的一项）
class AcademicTerm {
  final String id;
  final String name;
  final String nameZh;
  final DateTime week1Start; // 归一化为第 1 周周一
  final int totalWeeks;
  final List<int> teachingWeeks;
  final DateTime? orientationWeekStart;
  final DateTime? assessmentStart;
  final DateTime? assessmentEnd;
  final DateTime? semesterEnd;
  final List<CalendarHolidayEntry> holidays;

  const AcademicTerm({
    required this.id,
    required this.name,
    required this.nameZh,
    required this.week1Start,
    required this.totalWeeks,
    this.teachingWeeks = const [],
    this.orientationWeekStart,
    this.assessmentStart,
    this.assessmentEnd,
    this.semesterEnd,
    this.holidays = const [],
  });

  String localizedName({required bool isEn}) {
    if (isEn) return name.isNotEmpty ? name : nameZh;
    return nameZh.isNotEmpty ? nameZh : name;
  }

  /// 公式：week = floor((date - week1Start).inDays / 7) + 1
  int weekOfDate(DateTime date) {
    final diff = dateOnly(date).difference(mondayOf(week1Start)).inDays;
    return (diff / 7).floor() + 1;
  }

  /// 第 [week] 周的周一（支持 week <= 0 与 week > totalWeeks）
  DateTime weekStartDate(int week) =>
      mondayOf(week1Start).add(Duration(days: (week - 1) * 7));

  /// 第 [week] 周的周日
  DateTime weekEndDate(int week) => weekStartDate(week).add(const Duration(days: 6));

  /// 计算第 [week] 周对应的学期边界状态
  WeekStatusInfo evaluateWeek(int week) {
    final start = weekStartDate(week);
    final end = weekEndDate(week);

    if (week < 1) {
      if (orientationWeekStart != null) {
        final oriStart = dateOnly(orientationWeekStart!);
        final oriEnd = oriStart.add(const Duration(days: 6));
        if (!end.isBefore(oriStart) && !start.isAfter(oriEnd)) {
          return WeekStatusInfo(
            term: this,
            week: week,
            startDate: start,
            endDate: end,
            periodStatus: WeekPeriodStatus.orientation,
          );
        }
      }
      return WeekStatusInfo(
        term: this,
        week: week,
        startDate: start,
        endDate: end,
        periodStatus: WeekPeriodStatus.beforeSemester,
      );
    }

    if (week <= totalWeeks) {
      return WeekStatusInfo(
        term: this,
        week: week,
        startDate: start,
        endDate: end,
        periodStatus: WeekPeriodStatus.teaching,
      );
    }

    if (assessmentStart != null && assessmentEnd != null) {
      final aStart = dateOnly(assessmentStart!);
      final aEnd = dateOnly(assessmentEnd!);
      if (!end.isBefore(aStart) && !start.isAfter(aEnd)) {
        return WeekStatusInfo(
          term: this,
          week: week,
          startDate: start,
          endDate: end,
          periodStatus: WeekPeriodStatus.assessment,
        );
      }
    }

    return WeekStatusInfo(
      term: this,
      week: week,
      startDate: start,
      endDate: end,
      periodStatus: WeekPeriodStatus.afterSemester,
    );
  }

  AcademicTerm copyWith({
    String? id,
    String? name,
    String? nameZh,
    DateTime? week1Start,
    int? totalWeeks,
    List<int>? teachingWeeks,
    DateTime? orientationWeekStart,
    DateTime? assessmentStart,
    DateTime? assessmentEnd,
    DateTime? semesterEnd,
    List<CalendarHolidayEntry>? holidays,
  }) =>
      AcademicTerm(
        id: id ?? this.id,
        name: name ?? this.name,
        nameZh: nameZh ?? this.nameZh,
        week1Start: week1Start != null ? mondayOf(week1Start) : this.week1Start,
        totalWeeks: totalWeeks ?? this.totalWeeks,
        teachingWeeks: teachingWeeks ?? this.teachingWeeks,
        orientationWeekStart: orientationWeekStart ?? this.orientationWeekStart,
        assessmentStart: assessmentStart ?? this.assessmentStart,
        assessmentEnd: assessmentEnd ?? this.assessmentEnd,
        semesterEnd: semesterEnd ?? this.semesterEnd,
        holidays: holidays ?? this.holidays,
      );

  static DateTime? _tryParseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(dateOnlyStr(s));
    return d != null ? dateOnly(d) : null;
  }

  factory AcademicTerm.fromJson(Map<String, dynamic> j) {
    final rawStart = _tryParseDate(j['week1Start']);
    if (rawStart == null) {
      throw const FormatException('Missing or invalid week1Start');
    }
    final total = ((j['totalWeeks'] as num?)?.toInt() ?? 12).clamp(1, 30);
    final rawTeaching = j['teachingWeeks'];
    final teaching = rawTeaching is List
        ? rawTeaching.map((e) => (e as num).toInt()).toList()
        : [for (var i = 1; i <= total; i++) i];
    final assessment = j['assessmentPeriod'] is Map
        ? Map<String, dynamic>.from(j['assessmentPeriod'] as Map)
        : null;
    final rawHolidays = j['holidays'];
    final holidays = rawHolidays is List
        ? rawHolidays
            .whereType<Map>()
            .map((m) => CalendarHolidayEntry.fromJson(Map<String, dynamic>.from(m)))
            .where((h) => h.date.length == 10)
            .toList()
        : const <CalendarHolidayEntry>[];

    final name = (j['name'] ?? j['nameZh'] ?? j['id'] ?? 'Semester').toString().trim();
    final nameZh = (j['nameZh'] ?? j['name'] ?? name).toString().trim();
    return AcademicTerm(
      id: (j['id'] ?? name).toString().trim(),
      name: name,
      nameZh: nameZh,
      week1Start: mondayOf(rawStart),
      totalWeeks: total,
      teachingWeeks: teaching,
      orientationWeekStart: _tryParseDate(j['orientationWeekStart']),
      assessmentStart: assessment != null ? _tryParseDate(assessment['start']) : null,
      assessmentEnd: assessment != null ? _tryParseDate(assessment['end']) : null,
      semesterEnd: _tryParseDate(j['semesterEnd']),
      holidays: holidays,
    );
  }
}

/// 完整的学术日历对象（对应 assets/academic_calendar.json）
class AcademicCalendar {
  final int schemaVersion;
  final String source;
  final String institution;
  final String academicYear;
  final List<AcademicTerm> terms;

  const AcademicCalendar({
    required this.schemaVersion,
    required this.source,
    required this.institution,
    required this.academicYear,
    required this.terms,
  });

  /// 按当前日期自动匹配最合适的学期（支持秋季/春季切换与学期空窗期）
  AcademicTerm resolveTermForDate(DateTime date) {
    if (terms.isEmpty) {
      return AcademicTerm(
        id: 'default',
        name: 'Current Semester',
        nameZh: '当前学期',
        week1Start: mondayOf(date),
        totalWeeks: 12,
      );
    }
    final d = dateOnly(date);
    final sorted = List<AcademicTerm>.from(terms)
      ..sort((a, b) => a.week1Start.compareTo(b.week1Start));

    // 1) 精确命中某个学期的 [orientation/week1Start, assessmentEnd/semesterEnd]
    for (final t in sorted) {
      final start = dateOnly(t.orientationWeekStart ?? t.week1Start);
      final end = dateOnly(t.assessmentEnd ?? t.semesterEnd ?? t.weekEndDate(t.totalWeeks));
      if (!d.isBefore(start) && !d.isAfter(end)) {
        return t;
      }
    }

    // 2) 若处于两个学期之间，归属即将开始的下一个学期（可显示「学期未开始」）
    for (final t in sorted) {
      final start = dateOnly(t.orientationWeekStart ?? t.week1Start);
      if (d.isBefore(start)) {
        return t;
      }
    }

    // 3) 晚于所有已知学期：返回最后一个学期（可显示「学期结束」）
    return sorted.last;
  }

  /// 聚合整份日历中全部特殊日期（去重按日期）
  List<CalendarHolidayEntry> get allHolidays {
    final map = <String, CalendarHolidayEntry>{};
    for (final t in terms) {
      for (final h in t.holidays) {
        map[h.date] = h;
      }
    }
    final list = map.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  factory AcademicCalendar.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Academic calendar root must be a JSON object');
    }
    final map = Map<String, dynamic>.from(decoded);
    final rawTerms = map['terms'];
    if (rawTerms is! List || rawTerms.isEmpty) {
      throw const FormatException('Academic calendar must contain a non-empty "terms" list');
    }
    final terms = rawTerms
        .whereType<Map>()
        .map((m) => AcademicTerm.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    if (terms.isEmpty) {
      throw const FormatException('No valid terms parsed from academic calendar JSON');
    }
    return AcademicCalendar(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      source: (map['source'] ?? '').toString(),
      institution: (map['institution'] ?? '').toString(),
      academicYear: (map['academicYear'] ?? '').toString(),
      terms: terms,
    );
  }
}

/// 手动覆盖的学期配置（来自「学期设置」表单）
class ManualSemesterConfig {
  final String name;
  final DateTime week1Start;
  final int totalWeeks;
  final String? selectedTermId;

  const ManualSemesterConfig({
    required this.name,
    required this.week1Start,
    required this.totalWeeks,
    this.selectedTermId,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'week1Start': fmtDate(mondayOf(week1Start)),
        'totalWeeks': totalWeeks,
        if (selectedTermId != null) 'selectedTermId': selectedTermId,
      };

  static ManualSemesterConfig? tryFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final d = DateTime.tryParse(dateOnlyStr((j['week1Start'] ?? '').toString()));
      if (d == null) return null;
      return ManualSemesterConfig(
        name: (j['name'] ?? '').toString().trim(),
        week1Start: mondayOf(d),
        totalWeeks: ((j['totalWeeks'] as num?)?.toInt() ?? 12).clamp(1, 30),
        selectedTermId: j['selectedTermId']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 学术日历服务：
/// - 加载内置 assets/academic_calendar.json 或用户导入的自定义校历 JSON
/// - 统一提供「当前激活学期」「按 week1Start 计算真实周数」「高置信假期 / 低置信非教学日」
/// - 支持「学期设置」手动覆写（学期名 / 第 1 周开始日 / 总周数）及低置信度日期手动修正
/// - 预留未来 iCal (.ics) 导入扩展接口
class AcademicCalendarService {
  AcademicCalendarService._();

  static const _customCalendarKvKey = 'academic_calendar_json_v1';
  static const _manualConfigKvKey = 'semester_manual_override_v1';
  static const _lowConfOverridesKvKey = 'calendar_low_conf_overrides_v1';

  static AcademicCalendar? _builtinCache;
  static AcademicCalendar? _effectiveCache;
  static Map<String, LowConfidenceOverride>? _lowConfCache;

  /// 内置兜底 BUV 2026/2027 学期（仅在极端测试环境无法读取 asset 时启用）
  static final AcademicCalendar _fallbackCalendar = AcademicCalendar(
    schemaVersion: 1,
    source: 'BUV 2026/2027 Fallback',
    institution: 'British University Vietnam',
    academicYear: '2026/2027',
    terms: [
      AcademicTerm(
        id: 'autumn-2026',
        name: 'Autumn Semester 2026',
        nameZh: '2026 秋季学期',
        week1Start: DateTime(2026, 9, 28),
        totalWeeks: 12,
        teachingWeeks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        orientationWeekStart: DateTime(2026, 9, 21),
        assessmentStart: DateTime(2026, 12, 21),
        assessmentEnd: DateTime(2027, 1, 3),
        semesterEnd: DateTime(2026, 12, 20),
      ),
      AcademicTerm(
        id: 'spring-2027',
        name: 'Spring Semester 2027',
        nameZh: '2027 春季学期',
        week1Start: DateTime(2027, 1, 18),
        totalWeeks: 12,
        teachingWeeks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        assessmentStart: DateTime(2027, 4, 19),
        assessmentEnd: DateTime(2027, 5, 2),
      ),
    ],
  );

  /// 初始占位学期（加载前使用，随后被 assets/academic_calendar.json 或用户配置替换）
  static AcademicTerm get defaultFallbackTerm => _fallbackCalendar.terms.first;

  /// 清空内存缓存（测试或更新配置后调用）
  static void clearCache() {
    _effectiveCache = null;
    _lowConfCache = null;
  }

  /// 加载内置 assets/academic_calendar.json
  static Future<AcademicCalendar> loadBuiltinCalendar({String? overrideRawJson}) async {
    if (_builtinCache != null && overrideRawJson == null) return _builtinCache!;
    try {
      final raw = overrideRawJson ?? await rootBundle.loadString('assets/academic_calendar.json');
      final parsed = AcademicCalendar.fromJsonString(raw);
      if (overrideRawJson == null) _builtinCache = parsed;
      return parsed;
    } catch (e) {
      debugPrint('[AcademicCalendarService] Failed to load assets/academic_calendar.json: $e');
      return _fallbackCalendar;
    }
  }

  /// 加载当前生效的学术日历（用户导入优先，否则内置 BUV 校历）
  static Future<AcademicCalendar> loadCalendar() async {
    if (_effectiveCache != null) return _effectiveCache!;
    try {
      final customRaw = await Repo.getKv(_customCalendarKvKey);
      if (customRaw != null && customRaw.trim().isNotEmpty) {
        _effectiveCache = AcademicCalendar.fromJsonString(customRaw);
        return _effectiveCache!;
      }
    } catch (_) {}
    _effectiveCache = await loadBuiltinCalendar();
    return _effectiveCache!;
  }

  /// 是否使用了用户自定义导入的校历 JSON
  static Future<bool> hasCustomCalendar() async {
    try {
      final customRaw = await Repo.getKv(_customCalendarKvKey);
      return customRaw != null && customRaw.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 导入学术日历 JSON（校验格式后持久化并清除缓存）
  static Future<AcademicCalendar> importCalendarJson(String rawJson) async {
    final parsed = AcademicCalendar.fromJsonString(rawJson);
    await Repo.setKv(_customCalendarKvKey, rawJson.trim());
    // 导入新校历时清除旧的手动覆盖，让新校历的 week1Start / totalWeeks 立即生效
    await Repo.setKv(_manualConfigKvKey, '');
    await Repo.setKv('semester_start', '');
    clearCache();
    Repo.notifyDataChanged();
    return parsed;
  }

  /// 恢复内置 BUV 学术日历
  static Future<void> resetToBuiltinCalendar() async {
    await Repo.setKv(_customCalendarKvKey, '');
    await Repo.setKv(_manualConfigKvKey, '');
    await Repo.setKv('semester_start', '');
    clearCache();
    Repo.notifyDataChanged();
  }

  /// 读取用户通过「学期设置」手动保存的覆盖配置
  static Future<ManualSemesterConfig?> getManualConfig() async {
    try {
      return ManualSemesterConfig.tryFromJson(await Repo.getKv(_manualConfigKvKey));
    } catch (_) {
      return null;
    }
  }

  /// 保存「学期设置」手动配置（同步写入 semester_start，保持全应用口径一致）
  static Future<void> saveManualConfig(ManualSemesterConfig cfg) async {
    await Repo.setKv(_manualConfigKvKey, jsonEncode(cfg.toJson()));
    await Repo.setSemesterStart(cfg.week1Start);
    clearCache();
    Repo.notifyDataChanged();
  }

  /// 清除手动覆盖，恢复按校历与当前日期自动匹配学期
  static Future<void> clearManualConfig() async {
    await Repo.setKv(_manualConfigKvKey, '');
    await Repo.setKv('semester_start', '');
    clearCache();
    Repo.notifyDataChanged();
  }

  /// 获取当前激活学期（优先用户手动配置 > 按当前日期从 academic_calendar.json 自动匹配）
  static Future<AcademicTerm> getActiveTerm({DateTime? now}) async {
    final cal = await loadCalendar();
    final refDate = now ?? DateTime.now();
    final autoTerm = cal.resolveTermForDate(refDate);
    final manual = await getManualConfig();

    if (manual != null) {
      AcademicTerm baseTerm = autoTerm;
      if (manual.selectedTermId != null && manual.selectedTermId!.isNotEmpty) {
        for (final t in cal.terms) {
          if (t.id == manual.selectedTermId) {
            baseTerm = t;
            break;
          }
        }
      }
      final customName = manual.name.trim();
      final datesChanged =
          dateOnly(manual.week1Start) != dateOnly(baseTerm.week1Start) ||
          manual.totalWeeks != baseTerm.totalWeeks;
      return AcademicTerm(
        id: baseTerm.id,
        name: customName.isNotEmpty ? customName : baseTerm.name,
        nameZh: customName.isNotEmpty ? customName : baseTerm.nameZh,
        week1Start: mondayOf(manual.week1Start),
        totalWeeks: manual.totalWeeks,
        teachingWeeks: [for (var i = 1; i <= manual.totalWeeks; i++) i],
        orientationWeekStart: datesChanged
            ? mondayOf(manual.week1Start).subtract(const Duration(days: 7))
            : baseTerm.orientationWeekStart,
        assessmentStart: datesChanged ? null : baseTerm.assessmentStart,
        assessmentEnd: datesChanged ? null : baseTerm.assessmentEnd,
        semesterEnd: mondayOf(manual.week1Start).add(Duration(days: manual.totalWeeks * 7 - 1)),
        holidays: baseTerm.holidays,
      );
    }

    // 兼容旧版单独设置过 semester_start 的老用户
    try {
      final legacyStart = await Repo.getKv('semester_start');
      if (legacyStart != null && legacyStart.trim().isNotEmpty) {
        final d = DateTime.tryParse(dateOnlyStr(legacyStart));
        if (d != null) {
          return autoTerm.copyWith(week1Start: mondayOf(d));
        }
      }
    } catch (_) {}

    return autoTerm;
  }

  /// 读取用户对 confidence=low 日期的手动覆盖表
  static Future<Map<String, LowConfidenceOverride>> getLowConfidenceOverrides() async {
    if (_lowConfCache != null) return _lowConfCache!;
    final out = <String, LowConfidenceOverride>{};
    try {
      final raw = await Repo.getKv(_lowConfOverridesKvKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in j.entries) {
          final v = e.value.toString();
          if (v == 'holiday') {
            out[dateOnlyStr(e.key)] = LowConfidenceOverride.holiday;
          } else if (v == 'normal') {
            out[dateOnlyStr(e.key)] = LowConfidenceOverride.normal;
          } else {
            out[dateOnlyStr(e.key)] = LowConfidenceOverride.neutral;
          }
        }
      }
    } catch (_) {}
    _lowConfCache = out;
    return out;
  }

  /// 设置单个低置信度日期的用户确认状态
  static Future<void> setLowConfidenceOverride(
    String date,
    LowConfidenceOverride status,
  ) async {
    final map = Map<String, LowConfidenceOverride>.from(await getLowConfidenceOverrides());
    final d = dateOnlyStr(date);
    if (status == LowConfidenceOverride.neutral) {
      map.remove(d);
    } else {
      map[d] = status;
    }
    final encoded = <String, String>{
      for (final e in map.entries)
        e.key: e.value == LowConfidenceOverride.holiday ? 'holiday' : 'normal',
    };
    await Repo.setKv(_lowConfOverridesKvKey, jsonEncode(encoded));
    _lowConfCache = map;
    Repo.notifyDataChanged();
  }

  /// 纯函数：将校历条目按置信度与用户覆盖拆分为「确认假期」与「中性非教学日」
  static ({
    Map<String, CalendarHolidayEntry> confirmedHolidays,
    Map<String, CalendarHolidayEntry> neutralNonTeachingDays,
  }) classifyCalendarEntries({
    required List<CalendarHolidayEntry> entries,
    required Map<String, LowConfidenceOverride> overrides,
  }) {
    final confirmed = <String, CalendarHolidayEntry>{};
    final neutral = <String, CalendarHolidayEntry>{};

    for (final h in entries) {
      if (h.confidence == CalendarHolidayConfidence.high) {
        confirmed[h.date] = h;
      } else {
        final ov = overrides[h.date] ?? LowConfidenceOverride.neutral;
        switch (ov) {
          case LowConfidenceOverride.holiday:
            confirmed[h.date] = h;
            break;
          case LowConfidenceOverride.neutral:
            neutral[h.date] = h;
            break;
          case LowConfidenceOverride.normal:
            break;
        }
      }
    }

    return (confirmedHolidays: confirmed, neutralNonTeachingDays: neutral);
  }

  /// 获取某日期范围内「已确认」的校历假期（high 置信度 + 用户手动确认为假期的 low 条目）
  static Future<Map<String, CalendarHolidayEntry>> getConfirmedHolidaysInRange(
    DateTime from,
    DateTime to,
  ) async {
    final cal = await loadCalendar();
    final overrides = await getLowConfidenceOverrides();
    final split = classifyCalendarEntries(
      entries: cal.allHolidays,
      overrides: overrides,
    );
    final result = <String, CalendarHolidayEntry>{};
    final startD = dateOnly(from);
    final endD = dateOnly(to);
    for (var d = startD; !d.isAfter(endD); d = d.add(const Duration(days: 1))) {
      final k = fmtDate(d);
      final hit = split.confirmedHolidays[k];
      if (hit != null) result[k] = hit;
    }
    return result;
  }

  /// 获取某日期范围内「待确认 / 非教学日」中性标记（仅未改为假期/正常的 low 置信度条目）
  static Future<Map<String, CalendarHolidayEntry>> getNonTeachingDaysInRange(
    DateTime from,
    DateTime to,
  ) async {
    final cal = await loadCalendar();
    final overrides = await getLowConfidenceOverrides();
    final split = classifyCalendarEntries(
      entries: cal.allHolidays,
      overrides: overrides,
    );
    final result = <String, CalendarHolidayEntry>{};
    final startD = dateOnly(from);
    final endD = dateOnly(to);
    for (var d = startD; !d.isAfter(endD); d = d.add(const Duration(days: 1))) {
      final k = fmtDate(d);
      final hit = split.neutralNonTeachingDays[k];
      if (hit != null) result[k] = hit;
    }
    return result;
  }
}
