import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 跑步轨迹单点（存入 runs.route_json 为 [{lat,lng,t}]）
class RoutePoint {
  final double lat;
  final double lng;
  final int t; // epoch ms
  final double? accuracy;

  const RoutePoint({
    required this.lat,
    required this.lng,
    required this.t,
    this.accuracy,
  });

  Map<String, dynamic> toCompactJson() => {
        'lat': double.parse(lat.toStringAsFixed(6)),
        'lng': double.parse(lng.toStringAsFixed(6)),
        't': t,
      };

  static RoutePoint? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    final t = (raw['t'] as num?)?.toInt();
    if (lat == null || lng == null || t == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    return RoutePoint(lat: lat, lng: lng, t: t);
  }

  static String encodeList(List<RoutePoint> points) =>
      jsonEncode(points.map((p) => p.toCompactJson()).toList());

  static List<RoutePoint> decodeList(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final out = <RoutePoint>[];
      for (final item in decoded) {
        final pt = tryFromJson(item);
        if (pt != null) out.add(pt);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// 跑步记录（对应 SQLite runs 表）
class RunRecord {
  int? id;
  String date; // yyyy-MM-dd
  int startTime; // epoch ms
  int? endTime; // epoch ms
  int durationSecs; // 运动时长（不含暂停）
  int totalSecs; // 总时长（含暂停）
  double distanceM; // 有效距离（米）
  int? avgPaceSecsPerKm; // 平均配速（秒/公里）
  int caloriesKcal; // 估算热量（kcal，自动同步饮食页）
  String? courseId; // 关联课程 id，null 表示自由跑/距离跑
  String? routeJson; // 轨迹 JSON：[{lat,lng,t}]
  String? note;

  RunRecord({
    this.id,
    required this.date,
    required this.startTime,
    this.endTime,
    required this.durationSecs,
    required this.totalSecs,
    required this.distanceM,
    this.avgPaceSecsPerKm,
    required this.caloriesKcal,
    this.courseId,
    this.routeJson,
    this.note,
  });

  double get distanceKm => distanceM / 1000.0;

  List<RoutePoint> decodeRoute() => RoutePoint.decodeList(routeJson);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'duration_secs': durationSecs,
        'total_secs': totalSecs,
        'distance_m': distanceM,
        'avg_pace_secs_per_km': avgPaceSecsPerKm,
        'calories_kcal': caloriesKcal,
        'course_id': courseId,
        'route_json': routeJson,
        'note': note,
      };

  factory RunRecord.fromMap(Map<String, Object?> m) => RunRecord(
        id: m['id'] as int?,
        date: (m['date'] ?? '').toString(),
        startTime: (m['start_time'] as num?)?.toInt() ?? 0,
        endTime: (m['end_time'] as num?)?.toInt(),
        durationSecs: (m['duration_secs'] as num?)?.toInt() ?? 0,
        totalSecs: (m['total_secs'] as num?)?.toInt() ?? 0,
        distanceM: (m['distance_m'] as num?)?.toDouble() ?? 0,
        avgPaceSecsPerKm: (m['avg_pace_secs_per_km'] as num?)?.toInt(),
        caloriesKcal: (m['calories_kcal'] as num?)?.toInt() ?? 0,
        courseId: m['course_id'] as String?,
        routeJson: m['route_json'] as String?,
        note: m['note'] as String?,
      );
}

/// 课程分段记录（对应 SQLite run_segments 表）
class RunSegmentRecord {
  int? id;
  int runId;
  int seq;
  String type; // warmup / run / fast / slow / walk / cooldown
  int? durationSecs;
  double? distanceM;
  int? avgPaceSecsPerKm;

  RunSegmentRecord({
    this.id,
    required this.runId,
    required this.seq,
    required this.type,
    this.durationSecs,
    this.distanceM,
    this.avgPaceSecsPerKm,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'run_id': runId,
        'seq': seq,
        'type': type,
        'duration_secs': durationSecs,
        'distance_m': distanceM,
        'avg_pace_secs_per_km': avgPaceSecsPerKm,
      };

  factory RunSegmentRecord.fromMap(Map<String, Object?> m) => RunSegmentRecord(
        id: m['id'] as int?,
        runId: (m['run_id'] as num).toInt(),
        seq: (m['seq'] as num).toInt(),
        type: (m['type'] ?? 'run').toString(),
        durationSecs: (m['duration_secs'] as num?)?.toInt(),
        distanceM: (m['distance_m'] as num?)?.toDouble(),
        avgPaceSecsPerKm: (m['avg_pace_secs_per_km'] as num?)?.toInt(),
      );
}

/// 跑步课程单段定义（对应 assets/running_courses.json）
class RunningCourseSegment {
  final String type; // warmup / run / fast / slow / walk / cooldown
  final int? durationSeconds;
  final double? durationMeters;
  final String voice;

  const RunningCourseSegment({
    required this.type,
    this.durationSeconds,
    this.durationMeters,
    required this.voice,
  });

  bool get isDistanceBased => durationMeters != null && durationMeters! > 0;

  factory RunningCourseSegment.fromJson(Map<String, dynamic> j) => RunningCourseSegment(
        type: (j['type'] ?? 'run').toString(),
        durationSeconds: (j['durationSeconds'] as num?)?.toInt(),
        durationMeters: (j['durationMeters'] as num?)?.toDouble() ??
            (j['distanceMeters'] as num?)?.toDouble(),
        voice: (j['voice'] ?? j['voicePrompt'] ?? '').toString(),
      );
}

/// 跑步课程定义（对应 assets/running_courses.json）
class RunningCourse {
  final String id;
  final String name;
  final String nameEn;
  final int level;
  final String levelLabel;
  final int? estimatedMinutes;
  final int? estimatedKcal;
  final double? targetDistanceKm;
  final String description;
  final String type; // 'free' | 'course'
  final List<RunningCourseSegment> segments;

  const RunningCourse({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.level,
    required this.levelLabel,
    this.estimatedMinutes,
    this.estimatedKcal,
    this.targetDistanceKm,
    required this.description,
    required this.type,
    required this.segments,
  });

  bool get isFree => type == 'free';

  /// 是否属于按距离分段的课程（如 3/5/10 公里分段跑）
  bool get isDistanceCourse =>
      segments.isNotEmpty && segments.every((s) => s.isDistanceBased);

  /// 是否包含任何按距离分段（含混合课程如 5×400m）
  bool get hasDistanceSegments => segments.any((s) => s.isDistanceBased);

  String localizedName({required bool isEn}) =>
      isEn && nameEn.isNotEmpty ? nameEn : name;

  factory RunningCourse.fromJson(Map<String, dynamic> j) {
    final rawSegs = j['segments'];
    final segs = rawSegs is List
        ? rawSegs
            .whereType<Map>()
            .map((m) => RunningCourseSegment.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : const <RunningCourseSegment>[];
    return RunningCourse(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      nameEn: (j['nameEn'] ?? j['name'] ?? '').toString(),
      level: (j['level'] as num?)?.toInt() ?? 1,
      levelLabel: (j['levelLabel'] ?? '').toString(),
      estimatedMinutes: (j['estimatedMinutes'] as num?)?.toInt(),
      estimatedKcal: (j['estimatedKcal'] as num?)?.toInt(),
      targetDistanceKm: (j['targetDistanceKm'] as num?)?.toDouble(),
      description: (j['description'] ?? '').toString(),
      type: (j['type'] ?? 'course').toString(),
      segments: segs,
    );
  }
}

/// 课程分段类型元信息（复用 running_courses.json 中 segmentTypes 映射）
class SegmentTypeMeta {
  final String key;
  final String labelZh;
  final String labelEn;
  final int colorValue;

  const SegmentTypeMeta({
    required this.key,
    required this.labelZh,
    required this.labelEn,
    required this.colorValue,
  });

  String localizedLabel({required bool isEn}) => isEn ? labelEn : labelZh;
}

/// 加载 assets/running_courses.json 的课程目录与分段类型映射服务
class RunningCourseCatalog {
  RunningCourseCatalog._();

  static List<RunningCourse>? _cache;
  static Map<String, SegmentTypeMeta> _segmentTypes = Map.of(_defaultSegmentTypes);

  static const Map<String, SegmentTypeMeta> _defaultSegmentTypes = {
    'warmup': SegmentTypeMeta(key: 'warmup', labelZh: '热身', labelEn: 'Warm-up', colorValue: 0xFFFFB74D),
    'run': SegmentTypeMeta(key: 'run', labelZh: '慢跑', labelEn: 'Easy Run', colorValue: 0xFF4FC3F7),
    'fast': SegmentTypeMeta(key: 'fast', labelZh: '快跑', labelEn: 'Fast Run', colorValue: 0xFFEF5350),
    'slow': SegmentTypeMeta(key: 'slow', labelZh: '慢跑恢复', labelEn: 'Recovery Jog', colorValue: 0xFF81C784),
    'walk': SegmentTypeMeta(key: 'walk', labelZh: '快走', labelEn: 'Brisk Walk', colorValue: 0xFFBDBDBD),
    'cooldown': SegmentTypeMeta(key: 'cooldown', labelZh: '放松', labelEn: 'Cool-down', colorValue: 0xFF9575CD),
  };

  /// 获取某段类型对应的中文/英文名称与颜色（自动复用 running_courses.json 的 segmentTypes）
  static SegmentTypeMeta segmentMeta(String type) {
    final key = type.trim().toLowerCase();
    return _segmentTypes[key] ??
        _defaultSegmentTypes[key] ??
        SegmentTypeMeta(key: key, labelZh: key, labelEn: key, colorValue: 0xFF4FC3F7);
  }

  static int _parseHexColor(String? hex, int fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    final clean = hex.trim().replaceFirst('#', '');
    final full = clean.length == 6 ? 'FF$clean' : clean;
    return int.tryParse(full, radix: 16) ?? fallback;
  }

  static Future<List<RunningCourse>> loadAll({String? overrideRawJson}) async {
    if (_cache != null && overrideRawJson == null) return _cache!;
    try {
      final raw = overrideRawJson ?? await rootBundle.loadString('assets/running_courses.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      final rawTypes = decoded['segmentTypes'];
      if (rawTypes is Map) {
        final parsedTypes = Map<String, SegmentTypeMeta>.of(_defaultSegmentTypes);
        for (final entry in rawTypes.entries) {
          final key = entry.key.toString().trim().toLowerCase();
          if (entry.value is Map) {
            final m = Map<String, dynamic>.from(entry.value as Map);
            final def = _defaultSegmentTypes[key];
            parsedTypes[key] = SegmentTypeMeta(
              key: key,
              labelZh: (m['label'] ?? def?.labelZh ?? key).toString(),
              labelEn: (m['labelEn'] ?? def?.labelEn ?? m['label'] ?? key).toString(),
              colorValue: _parseHexColor(m['color']?.toString(), def?.colorValue ?? 0xFF4FC3F7),
            );
          }
        }
        _segmentTypes = parsedTypes;
      }

      final list = (decoded['courses'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => RunningCourse.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (overrideRawJson == null) _cache = list;
      return list;
    } catch (e) {
      debugPrint('[RunningCourseCatalog] Failed to load running_courses.json: $e');
      return const [];
    }
  }
}
