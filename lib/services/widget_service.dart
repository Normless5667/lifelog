import 'package:flutter/services.dart';

import '../db/repo.dart';
import '../models/models.dart';
import '../utils/date_utils.dart';
import 'battery_probe_service.dart';
import 'reminder_service.dart';
import 'step_service.dart';
import 'targets.dart';

/// 桌面小组件 (AppWidget) 同步服务：
/// - 负责从本地 SQLite 与计步器组装小组件展示的三行文案：
///   1) 今日课程（如：`📅 数据结构 09:00 · 大学英语 14:00`）
///   2) 剩余热量（如：`🔥 剩余热量：1420 kcal（已吃 580）`）
///   3) 今日步数（如：`👟 今日步数：4520 / 8000 步`）
/// - 通过 MethodChannel 调用原生 `LifeAssistantWidgetProvider.saveAndRefresh`
/// - 在首页加载完成、饮食增删改、训练/有氧增删改、步数更新（5分钟节流）以及 Activity onStop 时触发
class WidgetService {
  WidgetService._();

  static const _ch = MethodChannel('com.lifelog/reminders');
  static const _stepThrottleMs = 5 * 60 * 1000; // 步数实时跳动时每 5 分钟最多推送一次
  static int _lastStepPushMs = 0;
  static bool _initialized = false;
  static String _lastCourseLine = '';
  static String _lastCalorieLine = '';
  static String _lastStepLine = '';

  /// 初始化原生反向回调监听（如 MainActivity.onStop 触发兜底刷新、计步传感器 5 分钟节流回调）
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'syncWidgetOnStop') {
        await sync(force: true);
        return true;
      }
      if (call.method == 'onStepSensorThrottled') {
        await sync(fromStepUpdate: true);
        return true;
      }
      return null;
    });
  }

  /// 将今日课程列表格式化为简短单行文案，如：`📅 数据结构 09:00 · 大学英语 14:00`
  static String formatCoursesLine(List<Course> todayCourses) {
    if (todayCourses.isEmpty) {
      return '📅 今日暂无课程';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final parts = todayCourses.take(2).map((c) {
      final st = ReminderService.sectionStartTime(c.startSection);
      final shortName = c.name.length > 14 ? '${c.name.substring(0, 13)}…' : c.name;
      return '$shortName ${two(st.hour)}:${two(st.minute)}';
    }).toList();
    final suffix = todayCourses.length > 2 ? ' 等${todayCourses.length}节' : '';
    return '📅 ${parts.join(' · ')}$suffix';
  }

  /// 重新计算最新数据并推送到安卓桌面小组件
  /// - 若 [fromStepUpdate] 为 true 且距离上次步数推送不足 5 分钟，则自动节流跳过
  static Future<void> sync({
    bool force = false,
    bool fromStepUpdate = false,
  }) async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (fromStepUpdate && !force) {
        if (nowMs - _lastStepPushMs < _stepThrottleMs) {
          return;
        }
        _lastStepPushMs = nowMs;
      }

      final t = today();
      final meals = await Repo.getMeals(t);
      final weight = await Repo.latestBodyRecordWithWeight();
      final wKg = weight?.weight ?? 65;
      final stepState = await StepService.getTodaySteps(weightKg: wKg, syncWidget: false);
      final targets = await DailyTargets.load(date: t);

      final courses = await Repo.getCourses();
      final start = await Repo.getSemesterStart();
      final week = weekOfSemester(start, DateTime.now());
      final wd = DateTime.now().weekday;
      final todayCourses = courses
          .where((c) => c.weekday == wd && c.activeInWeek(week))
          .toList()
        ..sort((a, b) => a.startSection.compareTo(b.startSection));

      final totals = DayTotals.of(meals);
      final remKcal = (targets.calories - totals.calories).round();

      final courseLine = formatCoursesLine(todayCourses);
      final calorieLine = remKcal >= 0
          ? '🔥 剩余热量：$remKcal kcal（已吃 ${totals.calories.round()}）'
          : '🔥 超出热量：${remKcal.abs()} kcal（已吃 ${totals.calories.round()}）';
      final stepLine = '👟 今日步数：${stepState.todaySteps} / ${stepState.goal} 步';

      await pushLines(
        courseLine: courseLine,
        calorieLine: calorieLine,
        stepLine: stepLine,
      );
    } catch (_) {}
  }

  /// 直接推送已计算好的三行文案到原生 AppWidget（若内容未变化则跳过 IPC 调用，省电防刷）
  static Future<void> pushLines({
    required String courseLine,
    required String calorieLine,
    required String stepLine,
  }) async {
    if (courseLine == _lastCourseLine &&
        calorieLine == _lastCalorieLine &&
        stepLine == _lastStepLine) {
      return;
    }
    _lastCourseLine = courseLine;
    _lastCalorieLine = calorieLine;
    _lastStepLine = stepLine;
    try {
      BatteryProbeService.instance.recordWidgetRefresh();
      await _ch.invokeMethod('updateHomeWidget', {
        'course': courseLine,
        'calorie': calorieLine,
        'step': stepLine,
      });
    } catch (_) {}
  }

  /// 调用 Android 8.0+ 原生 requestPinAppWidget 一键将小组件固定到桌面
  static Future<bool> requestPinToHomeScreen() async {
    try {
      await sync(force: true);
      final ok = await _ch.invokeMethod<bool>('requestPinHomeWidget');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
