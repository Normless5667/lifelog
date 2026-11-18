import 'package:flutter/services.dart';

import '../db/repo.dart';
import '../models/models.dart';
import '../utils/date_utils.dart';
import 'bus_service.dart';
import 'weather_service.dart';

/// 课程时间映射 + 原生 Android 闹钟提醒 + 组间休息倒计时后台闹钟 + 系统时钟联动服务。
class ReminderService {
  ReminderService._();

  static const _ch = MethodChannel('com.lifelog/reminders');

  /// 计算第 [section] 节的开始时间（小时、分钟）
  static ({int hour, int minute}) sectionStartTime(int section) {
    final totalMinutes = 9 * 60 + (section - 1) * 30;
    return (hour: totalMinutes ~/ 60, minute: totalMinutes % 60);
  }

  /// 计算第 [endSection] 节的结束时间
  static ({int hour, int minute}) sectionEndTime(int endSection) {
    final totalMinutes = 9 * 60 + endSection * 30;
    return (hour: totalMinutes ~/ 60, minute: totalMinutes % 60);
  }

  static String formatRange(int startSection, int endSection) {
    final s = sectionStartTime(startSection);
    final e = sectionEndTime(endSection);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s.hour)}:${two(s.minute)}-${two(e.hour)}:${two(e.minute)}';
  }

  /// 是否开启上课提醒（默认开启）
  static Future<bool> isEnabled() async => (await Repo.getKv('course_reminder_enabled') ?? '1') == '1';

  static Future<void> setEnabled(bool v) async {
    await Repo.setKv('course_reminder_enabled', v ? '1' : '0');
    await syncAlarms();
  }

  /// 提前多少分钟提醒（默认 15 分钟）
  static Future<int> minutesBefore() async =>
      int.tryParse(await Repo.getKv('course_reminder_mins') ?? '') ?? 15;

  static Future<void> setMinutesBefore(int m) async {
    await Repo.setKv('course_reminder_mins', '$m');
    await syncAlarms();
  }

  /// 是否启用系统时钟 App 闹钟模式（可选开关）
  static Future<bool> useSystemClock() async =>
      (await Repo.getKv('course_use_system_clock') ?? '0') == '1';

  static Future<void> setUseSystemClock(bool v) async {
    await Repo.setKv('course_use_system_clock', v ? '1' : '0');
  }

  static Future<void> requestPermission() async {
    try {
      await _ch.invokeMethod('requestPermission');
    } catch (_) {}
  }

  /// 检查通知权限与渠道重要性（用于 ColorOS / 国产系统防静默降级引导与通知诊断页）
  static Future<({
    bool enabled,
    int importance,
    bool vibrate,
    bool sound,
    bool exactAlarm,
    String channelId,
    String channelName,
    String device,
  })> checkNotificationStatus() async {
    try {
      final res = await _ch.invokeMethod<Map>('checkNotificationStatus');
      if (res != null) {
        return (
          enabled: (res['enabled'] as bool?) ?? true,
          importance: (res['importance'] as int?) ?? 4,
          vibrate: (res['vibrate'] as bool?) ?? true,
          sound: (res['sound'] as bool?) ?? true,
          exactAlarm: (res['exactAlarm'] as bool?) ?? true,
          channelId: (res['channelId'] ?? 'course_reminders_v2').toString(),
          channelName: (res['channelName'] ?? '生活助手·强提醒通知').toString(),
          device: (res['device'] ?? 'Android').toString(),
        );
      }
    } catch (_) {}
    return (
      enabled: true,
      importance: 4,
      vibrate: true,
      sound: true,
      exactAlarm: true,
      channelId: 'course_reminders_v2',
      channelName: '生活助手·强提醒通知',
      device: 'Android',
    );
  }

  static Future<void> openNotificationSettings() async {
    try {
      await _ch.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  static Future<void> openAppNotificationSettings() async {
    try {
      await _ch.invokeMethod('openAppNotificationSettings');
    } catch (_) {}
  }

  static Future<void> testNotification() async {
    await requestPermission();
    await _ch.invokeMethod('testNotification');
  }

  /// 将今日或下一节即将上的课写入系统自带「时钟」App 闹钟
  static Future<String?> setNextCourseInSystemClock() async {
    final minsBefore = await minutesBefore();
    final courses = await Repo.getCourses();
    final semesterStart = await Repo.getSemesterStart();
    final now = DateTime.now();

    for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
      final day = dateOnly(now).add(Duration(days: dayOffset));
      final week = weekOfSemester(semesterStart, day);
      final wd = day.weekday;
      final dayCourses = courses
          .where((c) => c.weekday == wd && c.activeInWeek(week))
          .toList()
        ..sort((a, b) => a.startSection.compareTo(b.startSection));
      for (final c in dayCourses) {
        final st = sectionStartTime(c.startSection);
        final classStart = DateTime(day.year, day.month, day.day, st.hour, st.minute);
        final trigger = classStart.subtract(Duration(minutes: minsBefore));
        if (trigger.isAfter(now)) {
          await _ch.invokeMethod('setSystemClockAlarm', {
            'hour': trigger.hour,
            'minute': trigger.minute,
            'message': '${c.name} ${c.location ?? ''}'.trim(),
            'skipUi': false,
          });
          String two(int n) => n.toString().padLeft(2, '0');
          return '${two(trigger.hour)}:${two(trigger.minute)}（${c.name}）';
        }
      }
    }
    return null;
  }

  /// 组间休息开始倒计时时注册后台精确闹钟（切后台/锁屏也能准时震动弹窗）
  static Future<void> scheduleRestAlarm(int seconds, {String? nextHint}) async {
    try {
      await _ch.invokeMethod('scheduleRestAlarm', {
        'seconds': seconds,
        'title': '⏱️ 组间休息结束！',
        'body': nextHint ?? '休息时间到，准备开始下一组训练吧 💪',
      });
    } catch (_) {}
  }

  static Future<void> cancelRestAlarm() async {
    try {
      await _ch.invokeMethod('cancelRestAlarm');
    } catch (_) {}
  }

  static Future<void> vibrateShort() async {
    try {
      await _ch.invokeMethod('vibrateShort');
    } catch (_) {}
  }

  static Future<void> setKeepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {}
  }

  /// 更新安卓桌面小组件 (AppWidget)：显示今日课程 + 剩余热量 + 今日步数
  static Future<void> updateHomeWidget({
    required String courseLine,
    required String calorieLine,
    required String stepLine,
  }) async {
    try {
      await _ch.invokeMethod('updateHomeWidget', {
        'course': courseLine,
        'calorie': calorieLine,
        'step': stepLine,
      });
    } catch (_) {}
  }

  /// 重新计算未来课程提醒 + 校车到站前提醒（仅周一至周五）+ 每日 07:00 天气简报，注册到 Android AlarmManager
  static Future<int> syncAlarms() async {
    try {
      final enabled = await isEnabled();
      final now = DateTime.now();
      final items = <Map<String, Object>>[];

      if (enabled) {
        final minsBefore = await minutesBefore();
        final courses = await Repo.getCourses();
        final semesterStart = await Repo.getSemesterStart();

        for (var dayOffset = 0; dayOffset < 10; dayOffset++) {
          final day = dateOnly(now).add(Duration(days: dayOffset));
          final week = weekOfSemester(semesterStart, day);
          final wd = day.weekday;
          for (final Course c in courses) {
            if (c.weekday != wd || !c.activeInWeek(week)) continue;
            final st = sectionStartTime(c.startSection);
            final classStart = DateTime(day.year, day.month, day.day, st.hour, st.minute);
            final trigger = classStart.subtract(Duration(minutes: minsBefore));
            if (trigger.isAfter(now)) {
              final timeStr = formatRange(c.startSection, c.endSection);
              final loc = (c.location != null && c.location!.isNotEmpty) ? ' @ ${c.location}' : '';
              items.add({
                'triggerAt': trigger.millisecondsSinceEpoch,
                'title': '🔔 还有 $minsBefore 分钟上课：${c.name}',
                'body': '$timeStr$loc${c.teacher?.isNotEmpty == true ? ' · ${c.teacher}' : ''}',
              });
            }
          }
        }
      }

      // 校车到站前提醒（仅周一至周五）
      final busItems = await BusService.buildBusAlarmItems();
      items.addAll(busItems);

      // 每日 07:00 晨间天气简报
      final weather = await WeatherService.getWeather();
      final weatherSummary = weather?.summaryLine ?? '早安！点开生活助手查看今日课程、天气与校车时刻。';
      for (var dayOffset = 0; dayOffset < 3; dayOffset++) {
        final day = dateOnly(now).add(Duration(days: dayOffset));
        final morning7 = DateTime(day.year, day.month, day.day, 7, 0);
        if (morning7.isAfter(now)) {
          items.add({
            'triggerAt': morning7.millisecondsSinceEpoch,
            'title': '🌤️ 生活助手 · 晨间天气与日程简报',
            'body': weatherSummary,
          });
        }
      }

      final count = await _ch.invokeMethod<int>('scheduleAll', {'items': items});
      return count ?? items.length;
    } catch (_) {
      return 0;
    }
  }
}
