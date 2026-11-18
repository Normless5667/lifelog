import 'package:flutter/services.dart';

import '../db/repo.dart';
import '../utils/date_utils.dart';
import 'widget_service.dart';

/// 手机硬件级计步器服务（基于 Android Sensor.TYPE_STEP_COUNTER）。
/// TYPE_STEP_COUNTER 返回的是开机以来的总步数，因此按天存储基准值 (baseline)，
/// 每日零点切换日期时自动重置基准，并支持将今日步数折算为活动消耗 kcal。
class StepService {
  StepService._();

  static const _ch = MethodChannel('com.lifelog/reminders');
  static const defaultGoal = 8000;

  static Future<void> requestPermission() async {
    try {
      await _ch.invokeMethod('requestStepPermission');
    } catch (_) {}
  }

  static Future<int> stepGoal() async =>
      int.tryParse(await Repo.getKv('daily_step_goal') ?? '') ?? defaultGoal;

  static Future<void> setStepGoal(int goal) =>
      Repo.setKv('daily_step_goal', '$goal');

  /// 读取今日步数状态：
  /// - [supported] 设备是否有计步传感器
  /// - [granted] 是否已授予定步权限
  /// - [todaySteps] 今日已走步数
  /// - [burnedKcal] 步数折算消耗千卡（约每 1000 步 0.55 × 体重kg kcal，默认约 35~40 kcal / 千步）
  /// - [syncWidget] 若为 true，当步数变化时以 5 分钟节流触发桌面小组件更新
  static Future<({
    bool supported,
    bool granted,
    int todaySteps,
    int goal,
    double burnedKcal,
  })> getTodaySteps({double weightKg = 65, bool syncWidget = true}) async {
    final goal = await stepGoal();
    final t = today();
    final savedToday = int.tryParse(await Repo.getKv('steps_val_$t') ?? '') ?? 0;

    try {
      final res = await _ch.invokeMethod<Map>('getStepSensorState');
      if (res != null) {
        final supported = (res['supported'] as bool?) ?? false;
        final granted = (res['granted'] as bool?) ?? true;
        final rawSteps = (res['rawSteps'] as int?) ?? -1;

        if (supported && rawSteps >= 0) {
          final baseDate = await Repo.getKv('steps_base_date');
          var baseRaw = int.tryParse(await Repo.getKv('steps_base_raw') ?? '');

          // 新的一天，或者手机重启导致 rawSteps 小于基准值时，重置今日基准
          if (baseDate != t || baseRaw == null || rawSteps < baseRaw) {
            baseRaw = rawSteps - savedToday;
            await Repo.setKv('steps_base_date', t);
            await Repo.setKv('steps_base_raw', '$baseRaw');
          }

          final currentSteps = (rawSteps - baseRaw).clamp(0, 200000);
          await Repo.setKv('steps_val_$t', '$currentSteps');
          if (syncWidget && currentSteps != savedToday) {
            WidgetService.sync(fromStepUpdate: true);
          }
          final kcal = (currentSteps / 1000.0) * (weightKg * 0.55);
          return (
            supported: true,
            granted: granted,
            todaySteps: currentSteps,
            goal: goal,
            burnedKcal: kcal,
          );
        }
        return (
          supported: supported,
          granted: granted,
          todaySteps: savedToday,
          goal: goal,
          burnedKcal: (savedToday / 1000.0) * (weightKg * 0.55),
        );
      }
    } catch (_) {}

    return (
      supported: false,
      granted: false,
      todaySteps: savedToday,
      goal: goal,
      burnedKcal: (savedToday / 1000.0) * (weightKg * 0.55),
    );
  }
}
