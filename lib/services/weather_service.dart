import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../db/repo.dart';
import '../utils/date_utils.dart';
import 'battery_probe_service.dart';

class WeatherCityPreset {
  final String label;
  final String city;
  final double lat;
  final double lon;

  const WeatherCityPreset({
    required this.label,
    required this.city,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'city': city,
        'lat': lat,
        'lon': lon,
      };
}

class WeatherDailyForecast {
  final String date;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;
  final double precipProb;

  const WeatherDailyForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
    required this.precipProb,
  });

  bool get isRainy =>
      precipProb >= 45 ||
      (weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 99);

  String get emoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 3) return '⛅';
    if (isRainy) return '🌧️';
    return '🌤️';
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'maxTemp': maxTemp,
        'minTemp': minTemp,
        'weatherCode': weatherCode,
        'precipProb': precipProb,
      };

  factory WeatherDailyForecast.fromJson(Map<String, dynamic> j) => WeatherDailyForecast(
        date: (j['date'] ?? '').toString(),
        maxTemp: ((j['maxTemp'] ?? 28) as num).toDouble(),
        minTemp: ((j['minTemp'] ?? 22) as num).toDouble(),
        weatherCode: ((j['weatherCode'] ?? 1) as num).toInt(),
        precipProb: ((j['precipProb'] ?? 0) as num).toDouble(),
      );
}

class WeatherInfo {
  final double temperature;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;
  final double precipProb;
  final String city;
  final int fetchedAtMs;
  final List<WeatherDailyForecast> dailyForecast;

  const WeatherInfo({
    required this.temperature,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
    required this.precipProb,
    required this.city,
    required this.fetchedAtMs,
    this.dailyForecast = const [],
  });

  bool get isRainy =>
      precipProb >= 45 ||
      (weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 99);

  String get conditionText {
    if (weatherCode == 0) return '晴朗';
    if (weatherCode <= 3) return '多云';
    if (weatherCode == 45 || weatherCode == 48) return '有雾';
    if (weatherCode >= 51 && weatherCode <= 67) return '有雨';
    if (weatherCode >= 71 && weatherCode <= 77) return '降雪';
    if (weatherCode >= 80 && weatherCode <= 82) return '阵雨';
    if (weatherCode >= 95) return '雷阵雨';
    return '多云';
  }

  String get emoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 3) return '⛅';
    if (isRainy) return '🌧️';
    return '🌤️';
  }

  String get shortTip {
    if (isRainy) return '记得带伞 ☔';
    if (temperature >= 32) return '注意防晒补水 💧';
    return '适宜出行与运动 💪';
  }

  String get compactSubtitle =>
      '${fmtNum(minTemp)}~${fmtNum(maxTemp)}°C · 降水 ${fmtNum(precipProb)}% · $shortTip';

  String get summaryLine {
    final t = fmtNum(temperature);
    final range = '${fmtNum(minTemp)}~${fmtNum(maxTemp)}°C';
    if (isRainy) {
      return '今天 $t°C ($range) $conditionText（降水概率 ${fmtNum(precipProb)}%），出门上课记得带伞 ☔';
    }
    if (temperature >= 32) {
      return '今天 $t°C ($range) $conditionText，天气炎热注意多喝水防晒 💧';
    }
    return '今天 $t°C ($range) $conditionText，体感舒适，非常适合上课与运动 💪';
  }

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'maxTemp': maxTemp,
        'minTemp': minTemp,
        'weatherCode': weatherCode,
        'precipProb': precipProb,
        'city': city,
        'fetchedAtMs': fetchedAtMs,
        'dailyForecast': dailyForecast.map((d) => d.toJson()).toList(),
      };

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
        temperature: ((j['temperature'] ?? 26) as num).toDouble(),
        maxTemp: ((j['maxTemp'] ?? 29) as num).toDouble(),
        minTemp: ((j['minTemp'] ?? 22) as num).toDouble(),
        weatherCode: ((j['weatherCode'] ?? 1) as num).toInt(),
        precipProb: ((j['precipProb'] ?? 10) as num).toDouble(),
        city: (j['city'] ?? 'Ho Chi Minh City').toString(),
        fetchedAtMs: ((j['fetchedAtMs'] ?? 0) as num).toInt(),
        dailyForecast: ((j['dailyForecast'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => WeatherDailyForecast.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

/// Open-Meteo 免费免 Key 天气服务：
/// 1) 若用户在设置中手动指定了「天气城市」，优先使用用户指定的城市坐标（彻底不受代理/VPN 影响）
/// 2) 否则优先使用 `geolocator` 真实 GPS 定位（5 秒超时，首次启动请求权限）
/// 3) 若 GPS 权限被拒或超时，再 fallback 到 `https://ipwho.is/` IP 定位
/// 4) 定位结果本地缓存 **6 小时**，天气数据本地缓存 **30 分钟**（含未来 15 天逐日预报）
class WeatherService {
  WeatherService._();

  static const _channel = MethodChannel('com.lifelog/reminders');
  static const _weatherCacheKey = 'weather_cache_v3';
  static const _locCacheKey = 'weather_loc_cache_v1';
  static const _manualCityKey = 'weather_manual_city_v1';

  static const _weatherTtlMs = 30 * 60 * 1000; // 天气数据缓存 30 分钟
  static const _locCacheTtlMs = 6 * 60 * 60 * 1000; // 定位结果缓存 6 小时

  /// 常用城市一键预设（供设置页快速切换）
  static const presetCities = <WeatherCityPreset>[
    WeatherCityPreset(
      label: '胡志明市 (Ho Chi Minh City)',
      city: 'Ho Chi Minh City',
      lat: 10.8231,
      lon: 106.6297,
    ),
    WeatherCityPreset(
      label: '河内 / BUV (Hanoi)',
      city: 'Hanoi',
      lat: 20.9611,
      lon: 105.9465,
    ),
    WeatherCityPreset(
      label: '岘港 (Da Nang)',
      city: 'Da Nang',
      lat: 16.0544,
      lon: 108.2022,
    ),
    WeatherCityPreset(
      label: '香港 (Hong Kong)',
      city: 'Hong Kong',
      lat: 22.3193,
      lon: 114.1694,
    ),
    WeatherCityPreset(
      label: '上海 (Shanghai)',
      city: 'Shanghai',
      lat: 31.2304,
      lon: 121.4737,
    ),
    WeatherCityPreset(
      label: '北京 (Beijing)',
      city: 'Beijing',
      lat: 39.9042,
      lon: 116.4074,
    ),
    WeatherCityPreset(
      label: '广州 (Guangzhou)',
      city: 'Guangzhou',
      lat: 23.1291,
      lon: 113.2644,
    ),
    WeatherCityPreset(
      label: '深圳 (Shenzhen)',
      city: 'Shenzhen',
      lat: 22.5431,
      lon: 114.0579,
    ),
  ];

  /// 获取当前手动指定的城市（若为 null 则表示「自动 GPS 定位」）
  static Future<({String city, double lat, double lon})?> getManualCity() async {
    final raw = await Repo.getKv(_manualCityKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final c = (j['city'] ?? '').toString().trim();
      final lat = (j['lat'] as num?)?.toDouble();
      final lon = (j['lon'] as num?)?.toDouble();
      if (c.isNotEmpty && lat != null && lon != null) {
        return (city: c, lat: lat, lon: lon);
      }
    } catch (_) {}
    return null;
  }

  /// 设置为「自动 GPS 定位」模式（清除手动城市并刷新定位缓存）
  static Future<void> setAutoLocationMode() async {
    await Repo.setKv(_manualCityKey, '');
    await Repo.setKv(_locCacheKey, '');
    await Repo.setKv(_weatherCacheKey, '');
  }

  /// 手动指定天气城市（传入预设或地理编码结果）
  static Future<void> setManualCity({
    required String city,
    required double lat,
    required double lon,
  }) async {
    await Repo.setKv(
      _manualCityKey,
      jsonEncode({'city': city, 'lat': lat, 'lon': lon}),
    );
    await Repo.setKv(_weatherCacheKey, '');
  }

  /// 通过 Open-Meteo 免费 Geocoding 接口按城市名搜索并设为手动天气城市
  static Future<String> searchAndSetManualCity(String query) async {
    final q = query.trim();
    if (q.isEmpty) throw Exception('请输入城市名称');

    // 先匹配内置预设
    for (final p in presetCities) {
      if (p.city.toLowerCase() == q.toLowerCase() || p.label.contains(q)) {
        await setManualCity(city: p.city, lat: p.lat, lon: p.lon);
        return p.city;
      }
    }

    final url = Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(q)}&count=1&language=zh&format=json',
    );
    final resp = await http.get(url).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) {
      throw Exception('城市搜索服务暂时不可用 (${resp.statusCode})');
    }
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final results = (j['results'] as List?) ?? const [];
    if (results.isEmpty) {
      throw Exception('未找到城市「$q」，请尝试英文名或常见城市名');
    }
    final first = Map<String, dynamic>.from(results.first as Map);
    final name = (first['name'] ?? q).toString();
    final lat = ((first['latitude'] ?? 10.8231) as num).toDouble();
    final lon = ((first['longitude'] ?? 106.6297) as num).toDouble();
    await setManualCity(city: name, lat: lat, lon: lon);
    return name;
  }

  /// 根据 GPS 经纬度反查城市名（不依赖客户端出口 IP）
  static Future<String> _reverseGeocode(double lat, double lon) async {
    // 越南胡志明市及周边快速识别
    if (lat >= 10.3 && lat <= 11.2 && lon >= 106.3 && lon <= 107.1) {
      return 'Ho Chi Minh City';
    }
    // 越南河内 / BUV (Ecopark) 及周边快速识别
    if (lat >= 20.7 && lat <= 21.3 && lon >= 105.6 && lon <= 106.2) {
      return 'Hanoi';
    }
    try {
      final url = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lon&localityLanguage=en',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final city = (j['city'] ?? j['locality'] ?? j['principalSubdivision'] ?? '').toString().trim();
        if (city.isNotEmpty) return city;
      }
    } catch (_) {}
    return 'GPS (${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)})';
  }

  /// 解析当前应使用的天气坐标：手动指定 > 6小时缓存 > GPS(5秒超时) > IP兜底
  static Future<({double lat, double lon, String city})> _resolveLocation({
    bool forceRefresh = false,
  }) async {
    // 1. 用户在设置页手动指定了城市
    final manual = await getManualCity();
    if (manual != null) {
      return (lat: manual.lat, lon: manual.lon, city: manual.city);
    }

    // 2. 检查 6 小时定位缓存
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh) {
      final rawLoc = await Repo.getKv(_locCacheKey);
      if (rawLoc != null && rawLoc.isNotEmpty) {
        try {
          final j = jsonDecode(rawLoc) as Map<String, dynamic>;
          final cachedAt = ((j['cachedAtMs'] ?? 0) as num).toInt();
          if ((nowMs - cachedAt) < _locCacheTtlMs) {
            return (
              lat: ((j['lat'] ?? 10.8231) as num).toDouble(),
              lon: ((j['lon'] ?? 106.6297) as num).toDouble(),
              city: (j['city'] ?? 'Ho Chi Minh City').toString(),
            );
          }
        } catch (_) {}
      }
    }

    // 3. 优先真实 GPS 定位（Geolocator，5 秒超时，requestPermission 全局只调一次，绝不反复弹窗唤醒）
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          final alreadyAsked = await Repo.getKv('weather_gps_perm_asked_v1') == '1';
          if (!alreadyAsked) {
            await Repo.setKv('weather_gps_perm_asked_v1', '1');
            perm = await Geolocator.requestPermission();
          }
        }
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          BatteryProbeService.instance.recordGpsCall();
          Position? pos;
          try {
            pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 5),
              ),
            );
          } catch (_) {
            pos = await Geolocator.getLastKnownPosition();
          }
          if (pos != null) {
            final city = await _reverseGeocode(pos.latitude, pos.longitude);
            await Repo.setKv(
              _locCacheKey,
              jsonEncode({
                'lat': pos.latitude,
                'lon': pos.longitude,
                'city': city,
                'source': 'gps',
                'cachedAtMs': nowMs,
              }),
            );
            return (lat: pos.latitude, lon: pos.longitude, city: city);
          }
        }
      }
    } catch (_) {}

    // 4. Fallback：GPS 不可用或被拒绝时，使用 ipwho.is IP 定位兜底
    double lat = 10.8231;
    double lon = 106.6297;
    String city = 'Ho Chi Minh City';
    try {
      final ipResp = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 4));
      if (ipResp.statusCode == 200) {
        final ipJson = jsonDecode(utf8.decode(ipResp.bodyBytes)) as Map<String, dynamic>;
        if (ipJson['success'] == true) {
          lat = ((ipJson['latitude'] ?? lat) as num).toDouble();
          lon = ((ipJson['longitude'] ?? lon) as num).toDouble();
          city = (ipJson['city'] ?? city).toString();
        }
      }
    } catch (_) {}

    await Repo.setKv(
      _locCacheKey,
      jsonEncode({
        'lat': lat,
        'lon': lon,
        'city': city,
        'source': 'ip',
        'cachedAtMs': nowMs,
      }),
    );
    return (lat: lat, lon: lon, city: city);
  }

  static Future<WeatherInfo?> getWeather({bool forceRefresh = false}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rawCache = await Repo.getKv(_weatherCacheKey);
    WeatherInfo? cached;
    if (rawCache != null && rawCache.isNotEmpty) {
      try {
        cached = WeatherInfo.fromJson(jsonDecode(rawCache) as Map<String, dynamic>);
        if (!forceRefresh && (nowMs - cached.fetchedAtMs) < _weatherTtlMs) {
          return cached;
        }
      } catch (_) {}
    }

    try {
      final loc = await _resolveLocation(forceRefresh: forceRefresh);
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${loc.lat}&longitude=${loc.lon}'
        '&current=temperature_2m,weather_code'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=auto&forecast_days=15',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final cur = (j['current'] as Map<String, dynamic>?) ?? const {};
        final daily = (j['daily'] as Map<String, dynamic>?) ?? const {};
        final timeList = (daily['time'] as List?) ?? const [];
        final codeList = (daily['weather_code'] as List?) ?? const [];
        final maxList = (daily['temperature_2m_max'] as List?) ?? const [28];
        final minList = (daily['temperature_2m_min'] as List?) ?? const [22];
        final popList = (daily['precipitation_probability_max'] as List?) ?? const [0];

        final forecast = <WeatherDailyForecast>[];
        final dayCount = timeList.length.clamp(0, 15);
        for (var i = 0; i < dayCount; i++) {
          forecast.add(
            WeatherDailyForecast(
              date: timeList[i].toString(),
              weatherCode: i < codeList.length && codeList[i] != null
                  ? (codeList[i] as num).toInt()
                  : 1,
              maxTemp: i < maxList.length && maxList[i] != null
                  ? (maxList[i] as num).toDouble()
                  : 28,
              minTemp: i < minList.length && minList[i] != null
                  ? (minList[i] as num).toDouble()
                  : 22,
              precipProb: i < popList.length && popList[i] != null
                  ? (popList[i] as num).toDouble()
                  : 0,
            ),
          );
        }

        final info = WeatherInfo(
          temperature: ((cur['temperature_2m'] ?? 26) as num).toDouble(),
          weatherCode: ((cur['weather_code'] ?? 1) as num).toInt(),
          maxTemp: forecast.isNotEmpty
              ? forecast.first.maxTemp
              : (maxList.isNotEmpty ? (maxList.first as num).toDouble() : 28),
          minTemp: forecast.isNotEmpty
              ? forecast.first.minTemp
              : (minList.isNotEmpty ? (minList.first as num).toDouble() : 22),
          precipProb: forecast.isNotEmpty
              ? forecast.first.precipProb
              : (popList.isNotEmpty ? (popList.first as num).toDouble() : 0),
          city: loc.city,
          fetchedAtMs: nowMs,
          dailyForecast: forecast,
        );
        await Repo.setKv(_weatherCacheKey, jsonEncode(info.toJson()));
        return info;
      }
    } catch (_) {}
    return cached;
  }

  /// 调用 Android 原生 Intent 尝试拉起手机内置天气 App
  static Future<bool> openSystemWeatherApp() async {
    try {
      final res = await _channel.invokeMethod<bool>('openSystemWeather');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
