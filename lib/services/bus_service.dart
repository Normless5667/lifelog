import 'dart:convert';

import 'package:flutter/services.dart';

import '../db/repo.dart';
import '../utils/date_utils.dart';

class BusStopSchedule {
  final String name;
  final List<String> times;

  const BusStopSchedule({required this.name, required this.times});

  factory BusStopSchedule.fromJson(Map<String, dynamic> j) => BusStopSchedule(
        name: (j['name'] ?? '').toString(),
        times: ((j['times'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

class BusScheduleData {
  final String route;
  final String validPeriod;
  final String note;
  final String outboundTitle;
  final List<BusStopSchedule> outboundStops;
  final String inboundTitle;
  final List<BusStopSchedule> inboundStops;

  const BusScheduleData({
    required this.route,
    required this.validPeriod,
    required this.note,
    required this.outboundTitle,
    required this.outboundStops,
    required this.inboundTitle,
    required this.inboundStops,
  });
}

/// 校车时刻表服务（读取 assets/bus_schedule.json，支持常用站点选择、下一班倒计时与到站前提醒）
class BusService {
  BusService._();

  static BusScheduleData? _cached;

  static Future<BusScheduleData> load() async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString('assets/bus_schedule.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final outMap = (j['outbound'] as Map<String, dynamic>?) ?? const {};
    final inMap = (j['inbound'] as Map<String, dynamic>?) ?? const {};
    _cached = BusScheduleData(
      route: (j['route'] ?? 'Hai Ba Trung Route').toString(),
      validPeriod: (j['valid_period'] ?? '').toString(),
      note: (j['note'] ?? '').toString(),
      outboundTitle: (outMap['title'] ?? '去程').toString(),
      outboundStops: ((outMap['stops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BusStopSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      inboundTitle: (inMap['title'] ?? '回程').toString(),
      inboundStops: ((inMap['stops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BusStopSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
    return _cached!;
  }

  /// 所有可选的站点名称（去重，供选择常用站点）
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

  static Future<String> favoriteStop() async =>
      (await Repo.getKv('bus_favorite_stop')) ?? 'TIMES CITY';

  static Future<void> setFavoriteStop(String stop) =>
      Repo.setKv('bus_favorite_stop', stop);

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

  /// 获取某站点在当前时刻之后的下一班车信息（区分去程/回程，仅周一至周五发车）
  static Future<({
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
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

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
    String bestDir = '去程 → BUY CAMPUS';
    int bestDiff = 999999;

    for (final t in outStop.times) {
      final hm = _parseTime(t);
      if (hm == null) continue;
      final diff = hm.hour * 60 + hm.minute - nowMins;
      if (diff >= 0 && diff < bestDiff) {
        bestDiff = diff;
        bestTime = t;
        bestDir = '去程 → BUY CAMPUS';
      }
    }
    for (final t in inStop.times) {
      final hm = _parseTime(t);
      if (hm == null) continue;
      final diff = hm.hour * 60 + hm.minute - nowMins;
      if (diff >= 0 && diff < bestDiff) {
        bestDiff = diff;
        bestTime = t;
        bestDir = '回程 → Hai Ba Trung';
      }
    }

    if (bestTime == null) {
      return (
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
      stopName: fav,
      direction: bestDir,
      nextTime: bestTime,
      minutesUntil: bestDiff,
      isWeekend: false,
      outboundTimes: outStop.times,
      inboundTimes: inStop.times,
    );
  }

  /// 生成未来 7 天（仅周一到周五）常用站点的到站前提醒闹钟列表
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
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) continue;

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
              'body': '$dirLabel · 发车/到站时间 $t（Hai Ba Trung Route）',
            });
          }
        }
      }

      addTimes(outStop.times, '去程 → BUY CAMPUS');
      addTimes(inStop.times, '回程 → Hai Ba Trung');
    }
    return items;
  }
}
