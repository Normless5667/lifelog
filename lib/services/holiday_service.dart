import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../db/repo.dart';
import '../utils/date_utils.dart';
import 'weather_service.dart';

/// 单日公共假期信息
class HolidayInfo {
  final String date; // yyyy-MM-dd
  final String nameZh;
  final String nameEn;
  final String countryCode;
  final bool fromBuiltin;

  const HolidayInfo({
    required this.date,
    required this.nameZh,
    required this.nameEn,
    required this.countryCode,
    this.fromBuiltin = true,
  });

  String localizedName({required bool isEn}) {
    if (isEn) return nameEn.isNotEmpty ? nameEn : nameZh;
    return nameZh.isNotEmpty ? nameZh : nameEn;
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'zh': nameZh,
        'en': nameEn,
        'country': countryCode,
        'builtin': fromBuiltin,
      };

  factory HolidayInfo.fromJson(
    String date,
    Map<String, dynamic> j, {
    required String countryCode,
    bool fromBuiltin = true,
  }) =>
      HolidayInfo(
        date: dateOnlyStr(date),
        nameZh: (j['zh'] ?? j['localName'] ?? j['name'] ?? '').toString(),
        nameEn: (j['en'] ?? j['name'] ?? j['localName'] ?? '').toString(),
        countryCode: countryCode,
        fromBuiltin: fromBuiltin,
      );
}

/// 公共假期判断服务（本地内置优先 + Nager.Date 仅补充不覆盖 + kv 半年缓存 + 离线兜底）：
/// - 国家 ISO 代码从天气模块已有的城市名 / 坐标推断，绝不新增定位权限请求
/// - Nager.Date 免费 API 实测漏掉越南春节 (Tết) 与雄王纪念日，因此内置 assets/holidays.json 为权威基座
class HolidayService {
  HolidayService._();

  static const _countryOverrideKvKey = 'holiday_country_override_v1';
  static const _apiCacheTtlMs = 180 * 24 * 3600 * 1000; // 半年（每年最多拉 1~2 次）

  static Map<String, Map<String, HolidayInfo>>? _builtinCache;
  static final Map<String, Map<String, HolidayInfo>> _mergedYearCache = {};

  /// 根据城市名或经纬度推断国家 ISO 代码（无额外定位权限），查不到则回退默认 VN
  static String inferCountryFromCityAndCoords({
    String? city,
    double? lat,
    double? lon,
    String fallback = 'VN',
  }) {
    final c = (city ?? '').trim().toLowerCase();
    if (c.isNotEmpty) {
      const vnKeywords = [
        'hanoi', 'ha noi', 'ho chi minh', 'saigon', 'da nang', 'danang',
        'hai phong', 'nha trang', 'ecopark', 'buv', 'vietnam', 'viet nam',
        '河内', '胡志明', '岘港', '海防', '芽庄', '越南',
      ];
      for (final k in vnKeywords) {
        if (c.contains(k)) return 'VN';
      }
      const cnKeywords = [
        'beijing', 'shanghai', 'guangzhou', 'shenzhen', 'hong kong', 'hongkong',
        'chengdu', 'hangzhou', 'nanjing', 'wuhan', 'chongqing', 'xian', "xi'an",
        'suzhou', 'tianjin', 'china', 'macau', 'taipei',
        '北京', '上海', '广州', '深圳', '香港', '成都', '杭州', '南京', '武汉', '重庆', '西安', '苏州', '天津', '中国',
      ];
      for (final k in cnKeywords) {
        if (c.contains(k)) return 'CN';
      }
      const gbKeywords = [
        'london', 'manchester', 'edinburgh', 'birmingham', 'oxford', 'cambridge',
        'bristol', 'glasgow', 'liverpool', 'leeds', 'uk', 'united kingdom', 'britain',
        '伦敦', '曼彻斯特', '爱丁堡', '牛津', '剑桥', '英国',
      ];
      for (final k in gbKeywords) {
        if (c.contains(k)) return 'GB';
      }
      const usKeywords = [
        'new york', 'los angeles', 'san francisco', 'chicago', 'boston', 'seattle',
        'washington', 'austin', 'miami', 'dallas', 'houston', 'united states', 'usa',
        '纽约', '洛杉矶', '旧金山', '芝加哥', '波士顿', '西雅图', '华盛顿', '美国',
      ];
      for (final k in usKeywords) {
        if (c.contains(k)) return 'US';
      }
    }

    if (lat != null && lon != null && lat.isFinite && lon.isFinite) {
      // 越南大致经纬度范围
      if (lat >= 8.0 && lat <= 23.5 && lon >= 102.0 && lon <= 110.0) return 'VN';
      // 英国大致经纬度范围
      if (lat >= 49.8 && lat <= 60.9 && lon >= -8.6 && lon <= 1.8) return 'GB';
      // 美国本土大致经纬度范围
      if (lat >= 24.5 && lat <= 49.4 && lon >= -125.0 && lon <= -66.9) return 'US';
      // 中国大致经纬度范围
      if (lat >= 18.0 && lat <= 53.6 && lon >= 73.5 && lon <= 135.1) return 'CN';
    }
    return fallback;
  }

  /// 推断当前用户的国家代码（优先读取手动覆盖，否则复用天气模块已缓存的城市与坐标）
  static Future<String> resolveCountryCode() async {
    final override = (await Repo.getKv(_countryOverrideKvKey) ?? '').trim().toUpperCase();
    if (override.length == 2 && override != 'AU') {
      return override;
    }
    try {
      final manualCity = await WeatherService.getManualCity();
      if (manualCity != null) {
        return inferCountryFromCityAndCoords(
          city: manualCity.city,
          lat: manualCity.lat,
          lon: manualCity.lon,
        );
      }
      final weatherRaw = await Repo.getKv('weather_cache_v3');
      String? cachedCity;
      if (weatherRaw != null && weatherRaw.isNotEmpty) {
        final j = jsonDecode(weatherRaw) as Map<String, dynamic>;
        cachedCity = (j['city'] ?? '').toString();
      }
      double? lat;
      double? lon;
      final locRaw = await Repo.getKv('weather_loc_cache_v1');
      if (locRaw != null && locRaw.isNotEmpty) {
        final j = jsonDecode(locRaw) as Map<String, dynamic>;
        lat = (j['lat'] as num?)?.toDouble();
        lon = (j['lon'] as num?)?.toDouble();
        cachedCity ??= (j['city'] ?? '').toString();
      }
      return inferCountryFromCityAndCoords(city: cachedCity, lat: lat, lon: lon);
    } catch (_) {
      return 'VN';
    }
  }

  static Future<void> setCountryOverride(String? isoCode) async {
    await Repo.setKv(_countryOverrideKvKey, (isoCode ?? '').trim().toUpperCase());
    _mergedYearCache.clear();
  }

  /// 纯合并函数：本地内置假期优先，联网数据仅通过 putIfAbsent 补充本地缺失的日期，绝不覆盖本地数据
  static Map<String, HolidayInfo> mergeHolidayMaps({
    required Map<String, HolidayInfo> builtin,
    required Map<String, HolidayInfo> remoteSupplement,
  }) {
    final merged = Map<String, HolidayInfo>.from(builtin);
    for (final entry in remoteSupplement.entries) {
      merged.putIfAbsent(entry.key, () => entry.value);
    }
    return merged;
  }

  /// 解析 Nager.Date JSON 响应为补充表
  static Map<String, HolidayInfo> parseNagerDateJson(String body, String countryCode) {
    final out = <String, HolidayInfo>{};
    try {
      final list = jsonDecode(body);
      if (list is! List) return out;
      for (final item in list.whereType<Map>()) {
        final rawDate = (item['date'] ?? '').toString();
        if (rawDate.length < 10) continue;
        final d = dateOnlyStr(rawDate);
        final localName = (item['localName'] ?? item['name'] ?? '').toString().trim();
        final enName = (item['name'] ?? localName).toString().trim();
        if (enName.isEmpty) continue;
        out.putIfAbsent(
          d,
          () => HolidayInfo(
            date: d,
            nameZh: localName,
            nameEn: enName,
            countryCode: countryCode,
            fromBuiltin: false,
          ),
        );
      }
    } catch (_) {}
    return out;
  }

  /// 加载本地内置 assets/holidays.json
  static Future<Map<String, Map<String, HolidayInfo>>> loadBuiltinMap({
    String? overrideRawJson,
  }) async {
    if (_builtinCache != null && overrideRawJson == null) return _builtinCache!;
    final result = <String, Map<String, HolidayInfo>>{};
    try {
      final raw = overrideRawJson ?? await rootBundle.loadString('assets/holidays.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final countryEntry in decoded.entries) {
        final cc = countryEntry.key.toUpperCase();
        final daysMap = <String, HolidayInfo>{};
        if (countryEntry.value is Map) {
          final rawDays = Map<String, dynamic>.from(countryEntry.value as Map);
          for (final dEntry in rawDays.entries) {
            if (dEntry.value is Map) {
              final dKey = dateOnlyStr(dEntry.key);
              daysMap[dKey] = HolidayInfo.fromJson(
                dKey,
                Map<String, dynamic>.from(dEntry.value as Map),
                countryCode: cc,
                fromBuiltin: true,
              );
            }
          }
        }
        result[cc] = daysMap;
      }
    } catch (e) {
      debugPrint('[HolidayService] Failed to load assets/holidays.json: $e');
    }
    if (overrideRawJson == null) {
      _builtinCache = result;
    }
    return result;
  }

  /// 获取某国家+年份的完整假期表（本地内置优先 + Nager.Date 半年 kv 缓存补充，离线安全降级）
  static Future<Map<String, HolidayInfo>> getHolidaysForYear(
    int year, {
    String? countryCode,
    bool allowNetwork = true,
  }) async {
    final cc = (countryCode ?? await resolveCountryCode()).toUpperCase();
    final cacheKey = '${cc}_$year';
    final inMem = _mergedYearCache[cacheKey];
    if (inMem != null) return inMem;

    // 1) 读取本地内置假期（筛选该年份）
    final allBuiltin = await loadBuiltinMap();
    final yearPrefix = '$year-';
    final builtinForYear = <String, HolidayInfo>{};
    final countryBuiltin = allBuiltin[cc] ?? const <String, HolidayInfo>{};
    for (final entry in countryBuiltin.entries) {
      if (entry.key.startsWith(yearPrefix)) {
        builtinForYear[entry.key] = entry.value;
      }
    }

    // 2) 读取 kv 中已缓存的 Nager.Date 补充表（180 天 TTL，避免每次启动请求）
    final kvKey = 'holidays_api_${cc}_$year';
    var remoteMap = <String, HolidayInfo>{};
    var needsFetch = allowNetwork;
    try {
      final cachedStr = await Repo.getKv(kvKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
        final fetchedAt = ((decoded['fetched_at'] ?? 0) as num).toInt();
        final rawItems = decoded['items'];
        if (rawItems is Map) {
          for (final e in rawItems.entries) {
            if (e.value is Map) {
              remoteMap[dateOnlyStr(e.key.toString())] = HolidayInfo.fromJson(
                e.key.toString(),
                Map<String, dynamic>.from(e.value as Map),
                countryCode: cc,
                fromBuiltin: false,
              );
            }
          }
        }
        final ageMs = DateTime.now().millisecondsSinceEpoch - fetchedAt;
        if (ageMs >= 0 && ageMs < _apiCacheTtlMs) {
          needsFetch = false;
        }
      }
    } catch (_) {}

    // 3) 若缓存过期且允许联网，静默拉取 Nager.Date 补充数据（失败不报错，直接用本地兜底）
    if (needsFetch) {
      try {
        final uri = Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/$cc');
        final resp = await http.get(uri).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
          final fetched = parseNagerDateJson(resp.body, cc);
          if (fetched.isNotEmpty) {
            remoteMap = fetched;
            await Repo.setKvSilent(
              kvKey,
              jsonEncode({
                'fetched_at': DateTime.now().millisecondsSinceEpoch,
                'items': {for (final e in fetched.entries) e.key: e.value.toJson()},
              }),
            );
          }
        }
      } catch (_) {
        // 离线或超时时静默使用本地内置数据
      }
    }

    final merged = mergeHolidayMaps(builtin: builtinForYear, remoteSupplement: remoteMap);
    _mergedYearCache[cacheKey] = merged;
    return merged;
  }

  /// 判断某天是否为公共假期
  static Future<HolidayInfo?> getHolidayForDate(
    DateTime day, {
    String? countryCode,
    bool allowNetwork = true,
  }) async {
    final map = await getHolidaysForYear(
      day.year,
      countryCode: countryCode,
      allowNetwork: allowNetwork,
    );
    return map[fmtDate(day)];
  }

  /// 批量查询日期区间内的全部公共假期（跨年自动合并）
  static Future<Map<String, HolidayInfo>> getHolidaysForRange(
    DateTime start,
    DateTime end, {
    String? countryCode,
    bool allowNetwork = true,
  }) async {
    final cc = (countryCode ?? await resolveCountryCode()).toUpperCase();
    final years = <int>{start.year, end.year};
    final out = <String, HolidayInfo>{};
    for (final y in years) {
      final yMap = await getHolidaysForYear(y, countryCode: cc, allowNetwork: allowNetwork);
      out.addAll(yMap);
    }
    final sStr = fmtDate(start);
    final eStr = fmtDate(end);
    out.removeWhere((k, _) => k.compareTo(sStr) < 0 || k.compareTo(eStr) > 0);
    return out;
  }

  @visibleForTesting
  static void clearMemoryCache() {
    _builtinCache = null;
    _mergedYearCache.clear();
  }
}
