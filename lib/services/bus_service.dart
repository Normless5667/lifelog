import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../db/repo.dart';
import '../utils/date_utils.dart';

class BusStopSchedule {
  final String name;
  final List<String> times;
  final double? lat;
  final double? lng;

  const BusStopSchedule({
    required this.name,
    required this.times,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'times': times,
      };

  factory BusStopSchedule.fromJson(Map<String, dynamic> j) => BusStopSchedule(
        name: (j['name'] ?? '').toString(),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        times: ((j['times'] as List?) ?? const []).map((e) => e.toString().trim()).toList(),
      );
}

class BusRouteData {
  final String id;
  final String name;
  final String nameEn;
  final String school;
  final String source; // 'builtin' | 'imported' | 'custom'
  final String timezone; // 默认 'Asia/Ho_Chi_Minh'
  final String validPeriod;
  final bool weekdaysOnly;
  final String note;
  final String outboundTitle;
  final List<BusStopSchedule> outboundStops;
  final String inboundTitle;
  final List<BusStopSchedule> inboundStops;

  const BusRouteData({
    required this.id,
    required this.name,
    required this.nameEn,
    this.school = '',
    this.source = 'custom',
    this.timezone = 'Asia/Ho_Chi_Minh',
    this.validPeriod = '',
    this.weekdaysOnly = true,
    this.note = '',
    required this.outboundTitle,
    required this.outboundStops,
    required this.inboundTitle,
    required this.inboundStops,
  });

  bool get isBuiltin => source == 'builtin';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'name_en': nameEn.isEmpty ? name : nameEn,
        'school': school,
        'source': source,
        'timezone': timezone,
        'valid_period': validPeriod,
        'weekdays_only': weekdaysOnly,
        if (note.isNotEmpty) 'note': note,
        'outbound': {
          'title': outboundTitle,
          'stops': outboundStops.map((s) => s.toJson()).toList(),
        },
        'inbound': {
          'title': inboundTitle,
          'stops': inboundStops.map((s) => s.toJson()).toList(),
        },
      };

  factory BusRouteData.fromJson(Map<String, dynamic> j, {String? overrideSource}) {
    final outMap = (j['outbound'] as Map<String, dynamic>?) ?? const {};
    final inMap = (j['inbound'] as Map<String, dynamic>?) ?? const {};
    final rawName = (j['name'] ?? j['route'] ?? '未命名路线').toString().trim();
    final rawId = (j['id'] ?? '').toString().trim();
    final genId = rawId.isNotEmpty
        ? rawId
        : 'route-${DateTime.now().millisecondsSinceEpoch}';
    return BusRouteData(
      id: genId,
      name: rawName,
      nameEn: (j['name_en'] ?? rawName).toString().trim(),
      school: (j['school'] ?? '').toString().trim(),
      source: overrideSource ?? (j['source'] ?? 'imported').toString(),
      timezone: (j['timezone'] ?? 'Asia/Ho_Chi_Minh').toString(),
      validPeriod: (j['valid_period'] ?? '').toString(),
      weekdaysOnly: (j['weekdays_only'] as bool?) ?? true,
      note: (j['note'] ?? '').toString(),
      outboundTitle: (outMap['title'] ?? '去程 (Outbound)').toString(),
      outboundStops: ((outMap['stops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BusStopSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      inboundTitle: (inMap['title'] ?? '回程 (Inbound)').toString(),
      inboundStops: ((inMap['stops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BusStopSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// 校车多路线服务（v1.3）：
/// - 内置路线：读取 `assets/bus_routes.json` 并合并 `assets/bus_schedule.json` 作为 BUV 数据源
/// - 用户自定义/导入路线：存于 `<app_data>/routes/<route_id>.json`
/// - 默认行为不变：首次安装直接选中 `buv-hai-ba-trung`
/// - 严格导入格式校验（指出具体第几个站点哪一项格式或班次数量不对）
class BusService {
  BusService._();

  static const defaultRouteId = 'buv-hai-ba-trung';
  static final _hhmmReg = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  static List<BusRouteData>? _cachedRoutes;

  static Future<Directory> _userRoutesDir() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}/routes');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 加载全部路线（内置 + `<app_data>/routes/*.json`）
  static Future<List<BusRouteData>> loadAllRoutes({bool forceReload = false}) async {
    if (_cachedRoutes != null && !forceReload) return _cachedRoutes!;
    final routes = <BusRouteData>[];

    // 1. 读取 assets/bus_routes.json + assets/bus_schedule.json (BUV 原始数据源)
    try {
      final rawPack = await rootBundle.loadString('assets/bus_routes.json');
      final packJson = jsonDecode(rawPack) as Map<String, dynamic>;
      final rawBuv = await rootBundle.loadString('assets/bus_schedule.json');
      final buvSchedule = jsonDecode(rawBuv) as Map<String, dynamic>;

      final list = (packJson['routes'] as List?) ?? const [];
      for (final item in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        if (m['id'] == defaultRouteId) {
          // 以 assets/bus_schedule.json 作为 BUV 内置路线的数据源
          m['outbound'] = buvSchedule['outbound'];
          m['inbound'] = buvSchedule['inbound'];
          m['valid_period'] = buvSchedule['valid_period'] ?? m['valid_period'];
          m['note'] = buvSchedule['note'] ?? '';
        }
        routes.add(BusRouteData.fromJson(m, overrideSource: 'builtin'));
      }
    } catch (_) {}

    // 兜底：如果 bus_routes.json 读取异常，直接用 bus_schedule.json 构造 BUV 内置路线
    if (routes.isEmpty) {
      final rawBuv = await rootBundle.loadString('assets/bus_schedule.json');
      final buvSchedule = jsonDecode(rawBuv) as Map<String, dynamic>;
      buvSchedule['id'] = defaultRouteId;
      buvSchedule['name'] = 'BUV · Hai Ba Trung Route';
      buvSchedule['name_en'] = 'BUV · Hai Ba Trung Route';
      buvSchedule['school'] = 'British University Vietnam';
      routes.add(BusRouteData.fromJson(buvSchedule, overrideSource: 'builtin'));
    }

    // 2. 读取用户目录 <app_data>/routes/<route_id>.json
    try {
      final dir = await _userRoutesDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        try {
          final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final r = BusRouteData.fromJson(j);
          if (r.id != defaultRouteId) {
            routes.removeWhere((existing) => existing.id == r.id);
            routes.add(r);
          }
        } catch (_) {}
      }
    } catch (_) {}

    _cachedRoutes = routes;
    return routes;
  }

  /// 当前选中的路线 ID（首次安装默认返回 `buv-hai-ba-trung`）
  static Future<String> activeRouteId() async =>
      (await Repo.getKv('bus_active_route_id')) ?? defaultRouteId;

  static Future<void> setActiveRouteId(String id) async {
    await Repo.setKv('bus_active_route_id', id);
  }

  /// 获取当前选中的路线数据（若找不到则自动回退到 BUV 默认路线）
  static Future<BusRouteData> load() async {
    final all = await loadAllRoutes();
    final activeId = await activeRouteId();
    return all.firstWhere(
      (r) => r.id == activeId,
      orElse: () => all.first,
    );
  }

  /// 校验单条路线 JSON 对象；通过时返回 null，失败时返回具体中文错误原因
  static String? validateRouteMap(Map<String, dynamic> j) {
    final name = (j['name'] ?? j['route'] ?? '').toString().trim();
    if (name.isEmpty) {
      return '导入失败：缺少路线名称 "name" 字段';
    }
    final out = j['outbound'];
    final inb = j['inbound'];
    if (out is! Map) {
      return '导入失败：缺少 "outbound"（去程）对象';
    }
    if (inb is! Map) {
      return '导入失败：缺少 "inbound"（回程）对象';
    }
    final outErr = _validateStopsSection(Map<String, dynamic>.from(out), '去程 (outbound)');
    if (outErr != null) return outErr;
    final inErr = _validateStopsSection(Map<String, dynamic>.from(inb), '回程 (inbound)');
    if (inErr != null) return inErr;
    return null;
  }

  static String? _validateStopsSection(Map<String, dynamic> sec, String label) {
    final stops = sec['stops'];
    if (stops is! List || stops.isEmpty) {
      return '导入失败：$label 的 "stops" 站点列表不能为空';
    }
    int? expectedLen;
    for (var i = 0; i < stops.length; i++) {
      final item = stops[i];
      final idx = i + 1;
      if (item is! Map) {
        return '导入失败：$label 第 $idx 个站点格式不是对象';
      }
      final sname = (item['name'] ?? '').toString().trim();
      if (sname.isEmpty) {
        return '导入失败：$label 第 $idx 个站点缺少名称 "name"';
      }
      final times = item['times'];
      if (times is! List || times.isEmpty) {
        return '导入失败：$label 第 $idx 个站点 "$sname" 的 "times" 不能为空';
      }
      for (final rawT in times) {
        final t = rawT.toString().trim();
        if (!_hhmmReg.hasMatch(t)) {
          return '导入失败：$label 第 $idx 个站点 "$sname" 的时间 "$t" 不是 HH:mm 格式（例如 07:40）';
        }
      }
      if (expectedLen == null) {
        expectedLen = times.length;
      } else if (times.length != expectedLen) {
        return '导入失败：$label 第 $idx 个站点 "$sname" 有 ${times.length} 个班次，与第 1 个站点的 $expectedLen 个班次数量不一致';
      }
    }
    return null;
  }

  /// 从 JSON 字符串校验并导入路线（支持单条路线 JSON 或含 `routes` 数组的路线包 JSON）
  static Future<BusRouteData> importRouteFromJsonString(String rawJson, {String source = 'imported'}) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (e) {
      throw FormatException('导入失败：JSON 语法错误（$e）');
    }
    if (decoded is! Map) {
      throw const FormatException('导入失败：JSON 顶层必须是一个对象 {...}');
    }
    final map = Map<String, dynamic>.from(decoded);
    Map<String, dynamic> targetMap = map;
    if (map['routes'] is List && (map['routes'] as List).isNotEmpty) {
      final first = (map['routes'] as List).first;
      if (first is Map) {
        targetMap = Map<String, dynamic>.from(first);
      }
    }

    final err = validateRouteMap(targetMap);
    if (err != null) {
      throw FormatException(err);
    }

    var route = BusRouteData.fromJson(targetMap, overrideSource: source);
    if (route.id == defaultRouteId) {
      route = BusRouteData.fromJson(
        {...targetMap, 'id': 'custom-${DateTime.now().millisecondsSinceEpoch}'},
        overrideSource: source,
      );
    }
    await saveUserRoute(route);
    return route;
  }

  /// 保存用户自定义或导入的路线到 `<app_data>/routes/<id>.json`
  static Future<void> saveUserRoute(BusRouteData route) async {
    final err = validateRouteMap(route.toJson());
    if (err != null) throw FormatException(err);
    final dir = await _userRoutesDir();
    final safeId = route.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final file = File('${dir.path}/$safeId.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(route.toJson()));
    await loadAllRoutes(forceReload: true);
  }

  /// 删除用户自定义/导入路线（内置路线不可删除）
  static Future<void> deleteUserRoute(String routeId) async {
    if (routeId == defaultRouteId) return;
    final dir = await _userRoutesDir();
    final safeId = routeId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final file = File('${dir.path}/$safeId.json');
    if (await file.exists()) {
      await file.delete();
    }
    if (await activeRouteId() == routeId) {
      await setActiveRouteId(defaultRouteId);
    }
    await loadAllRoutes(forceReload: true);
  }

  /// 生成空模板 JSON 字符串（供用户下载填写或分享学校路线）
  static String templateJsonString() {
    const tpl = {
      'id': 'my-university-route-1',
      'name': '示例大学 · 1号校车线',
      'name_en': 'Sample University · Route 1',
      'school': 'Sample University',
      'source': 'custom',
      'timezone': 'Asia/Ho_Chi_Minh',
      'valid_period': '2026 Fall Semester',
      'weekdays_only': true,
      'outbound': {
        'title': '去程 (市区 → 校区)',
        'stops': [
          {
            'name': '第一站 (City Center)',
            'lat': 21.0285,
            'lng': 105.8542,
            'times': ['07:30', '09:30', '13:00']
          },
          {
            'name': '第二站 (Subway Station)',
            'times': ['07:45', '09:45', '13:15']
          },
          {
            'name': '终点站 (Main Campus)',
            'times': ['08:15', '10:15', '13:45']
          }
        ]
      },
      'inbound': {
        'title': '回程 (校区 → 市区)',
        'stops': [
          {
            'name': '起点站 (Main Campus)',
            'times': ['12:00', '15:30', '17:30']
          },
          {
            'name': '第二站 (Subway Station)',
            'times': ['12:30', '16:00', '18:00']
          },
          {
            'name': '终点站 (City Center)',
            'times': ['12:45', '16:15', '18:15']
          }
        ]
      }
    };
    return const JsonEncoder.withIndent('  ').convert(tpl);
  }

  /// 当前路线下所有可选的站点名称（去重）
  static Future<List<String>> allStopNames() async {
    final data = await load();
    final set = <String>{};
    for (final s in data.outboundStops) {
      set.add(_cleanName(s.name));
    }
    for (final s in data.inboundStops) {
      set.add(_cleanName(s.name));
    }
    return set.toList();
  }

  static String _cleanName(String s) =>
      s.replaceAll('（到校）', '').replaceAll('（发车）', '').replaceAll('（终点）', '').trim();

  static Future<String> favoriteStop() async {
    final route = await load();
    final stops = await allStopNames();
    final saved = await Repo.getKv('bus_fav_stop_${route.id}') ??
        (route.id == defaultRouteId ? await Repo.getKv('bus_favorite_stop') : null);
    if (saved != null && stops.contains(saved)) return saved;
    if (stops.contains('TIMES CITY')) return 'TIMES CITY';
    return stops.isNotEmpty ? stops.first : 'TIMES CITY';
  }

  static Future<void> setFavoriteStop(String stop) async {
    final route = await load();
    await Repo.setKv('bus_fav_stop_${route.id}', stop);
    if (route.id == defaultRouteId) {
      await Repo.setKv('bus_favorite_stop', stop);
    }
  }

  static Future<bool> reminderEnabled() async =>
      (await Repo.getKv('bus_reminder_enabled') ?? '1') == '1';

  static Future<void> setReminderEnabled(bool v) =>
      Repo.setKv('bus_reminder_enabled', v ? '1' : '0');

  static Future<int> reminderMinutesBefore() async =>
      int.tryParse(await Repo.getKv('bus_reminder_mins') ?? '') ?? 10;

  static Future<void> setReminderMinutesBefore(int mins) =>
      Repo.setKv('bus_reminder_mins', '$mins');

  static ({int hour, int minute})? _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return (hour: h, minute: m);
  }

  /// 获取当前路线、常用站点在当前时刻之后的下一班车信息
  static Future<({
    String routeName,
    String stopName,
    String direction,
    String nextTime,
    int minutesUntil,
    bool isWeekend,
    List<String> outboundTimes,
    List<String> inboundTimes,
  })> nextBusSummary() async {
    final data = await load();
    final fav = await favoriteStop();
    final now = DateTime.now();
    final isWeekend = data.weekdaysOnly &&
        (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday);

    final outStop = data.outboundStops.firstWhere(
      (s) => _cleanName(s.name) == fav,
      orElse: () => data.outboundStops.first,
    );
    final inStop = data.inboundStops.firstWhere(
      (s) => _cleanName(s.name) == fav,
      orElse: () => data.inboundStops.first,
    );

    if (isWeekend) {
      return (
        routeName: data.name,
        stopName: fav,
        direction: '周末停运（仅周一至周五运行）',
        nextTime: outStop.times.first,
        minutesUntil: -1,
        isWeekend: true,
        outboundTimes: outStop.times,
        inboundTimes: inStop.times,
      );
    }

    final nowMins = now.hour * 60 + now.minute;
    String? bestTime;
    String bestDir = data.outboundTitle;
    int bestDiff = 999999;

    for (final t in outStop.times) {
      final hm = _parseTime(t);
      if (hm == null) continue;
      final diff = hm.hour * 60 + hm.minute - nowMins;
      if (diff >= 0 && diff < bestDiff) {
        bestDiff = diff;
        bestTime = t;
        bestDir = data.outboundTitle;
      }
    }
    for (final t in inStop.times) {
      final hm = _parseTime(t);
      if (hm == null) continue;
      final diff = hm.hour * 60 + hm.minute - nowMins;
      if (diff >= 0 && diff < bestDiff) {
        bestDiff = diff;
        bestTime = t;
        bestDir = data.inboundTitle;
      }
    }

    if (bestTime == null) {
      return (
        routeName: data.name,
        stopName: fav,
        direction: '今日班次已结束（明日首班 ${outStop.times.first}）',
        nextTime: outStop.times.first,
        minutesUntil: -1,
        isWeekend: false,
        outboundTimes: outStop.times,
        inboundTimes: inStop.times,
      );
    }

    return (
      routeName: data.name,
      stopName: fav,
      direction: bestDir,
      nextTime: bestTime,
      minutesUntil: bestDiff,
      isWeekend: false,
      outboundTimes: outStop.times,
      inboundTimes: inStop.times,
    );
  }

  /// 生成未来 5 天常用站点的到站前提醒闹钟列表
  static Future<List<Map<String, Object>>> buildBusAlarmItems() async {
    if (!await reminderEnabled()) return [];
    final data = await load();
    final fav = await favoriteStop();
    final minsBefore = await reminderMinutesBefore();
    final now = DateTime.now();

    final outStop = data.outboundStops.firstWhere(
      (s) => _cleanName(s.name) == fav,
      orElse: () => data.outboundStops.first,
    );
    final inStop = data.inboundStops.firstWhere(
      (s) => _cleanName(s.name) == fav,
      orElse: () => data.inboundStops.first,
    );

    final items = <Map<String, Object>>[];
    for (var dayOffset = 0; dayOffset < 5; dayOffset++) {
      final day = dateOnly(now).add(Duration(days: dayOffset));
      if (data.weekdaysOnly &&
          (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday)) {
        continue;
      }

      void addTimes(List<String> times, String dirLabel) {
        for (final t in times) {
          final hm = _parseTime(t);
          if (hm == null) continue;
          final busTime = DateTime(day.year, day.month, day.day, hm.hour, hm.minute);
          final trigger = busTime.subtract(Duration(minutes: minsBefore));
          if (trigger.isAfter(now)) {
            items.add({
              'triggerAt': trigger.millisecondsSinceEpoch,
              'title': '🚌 校车还有 $minsBefore 分钟到站：$fav',
              'body': '${data.name} · $dirLabel · 到站时间 $t',
            });
          }
        }
      }

      addTimes(outStop.times, data.outboundTitle);
      addTimes(inStop.times, data.inboundTitle);
    }
    return items;
  }
}
