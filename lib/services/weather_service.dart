import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db/repo.dart';
import '../utils/date_utils.dart';

class WeatherInfo {
  final double temperature;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;
  final double precipProb;
  final String city;
  final int fetchedAtMs;

  const WeatherInfo({
    required this.temperature,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
    required this.precipProb,
    required this.city,
    required this.fetchedAtMs,
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
      };

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
        temperature: ((j['temperature'] ?? 26) as num).toDouble(),
        maxTemp: ((j['maxTemp'] ?? 29) as num).toDouble(),
        minTemp: ((j['minTemp'] ?? 22) as num).toDouble(),
        weatherCode: ((j['weatherCode'] ?? 1) as num).toInt(),
        precipProb: ((j['precipProb'] ?? 10) as num).toDouble(),
        city: (j['city'] ?? 'Hanoi').toString(),
        fetchedAtMs: ((j['fetchedAtMs'] ?? 0) as num).toInt(),
      );
}

/// Open-Meteo 免费免 Key 天气服务（带 30 分钟本地缓存 + IP 经纬度自动定位兜底）
class WeatherService {
  WeatherService._();

  static const _cacheKey = 'weather_cache_v1';
  static const _cacheTtlMs = 30 * 60 * 1000; // 30 分钟缓存

  static Future<WeatherInfo?> getWeather({bool forceRefresh = false}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rawCache = await Repo.getKv(_cacheKey);
    WeatherInfo? cached;
    if (rawCache != null) {
      try {
        cached = WeatherInfo.fromJson(jsonDecode(rawCache) as Map<String, dynamic>);
        if (!forceRefresh && (nowMs - cached.fetchedAtMs) < _cacheTtlMs) {
          return cached;
        }
      } catch (_) {}
    }

    try {
      // 默认河内 (BUV / Hai Ba Trung) 坐标，若 IP 定位成功则使用实时坐标
      double lat = 21.0285;
      double lon = 105.8542;
      String city = 'Hanoi';
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

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weather_code'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=auto&forecast_days=1',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final cur = (j['current'] as Map<String, dynamic>?) ?? const {};
        final daily = (j['daily'] as Map<String, dynamic>?) ?? const {};
        final maxList = (daily['temperature_2m_max'] as List?) ?? const [28];
        final minList = (daily['temperature_2m_min'] as List?) ?? const [22];
        final popList = (daily['precipitation_probability_max'] as List?) ?? const [0];

        final info = WeatherInfo(
          temperature: ((cur['temperature_2m'] ?? 26) as num).toDouble(),
          weatherCode: ((cur['weather_code'] ?? 1) as num).toInt(),
          maxTemp: (maxList.first as num).toDouble(),
          minTemp: (minList.first as num).toDouble(),
          precipProb: (popList.first as num).toDouble(),
          city: city,
          fetchedAtMs: nowMs,
        );
        await Repo.setKv(_cacheKey, jsonEncode(info.toJson()));
        return info;
      }
    } catch (_) {}
    return cached;
  }
}
