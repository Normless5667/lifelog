import 'package:flutter/services.dart';

import '../db/repo.dart';
import '../utils/date_utils.dart';
import 'nutrition.dart';
import 'usage_telemetry_service.dart';
import 'widget_service.dart';

/// 手机硬件级计步器服务（基于 Android Sensor.TYPE_STEP_COUNTER）。
/// - 步数写库节流到 ≥30 秒一次，且仅当步数发生实质变化时才写库，杜绝高频传感器导致持续唤醒
class StepService {
  StepService._();

  static const _ch = MethodChannel('com.lifelog/reminders');
  static const defaultGoal = 8000;
  static const _writeThrottleMs = 30 * 1000; // 写库节流 30 秒

  static int _lastWriteMs = 0;
  static int _lastWrittenSteps = -1;
  static String _lastWrittenDate = '';

  static Future<void> requestPermission() async {
    try {
      await _ch.invokeMethod('requestStepPermission');
    } catch (_) {}
  }

  static Future<int> stepGoal() async =>
      int.tryParse(await Repo.getKv('daily_step_goal') ?? '') ?? defaultGoal;

  static Future<void> setStepGoal(int goal) =>
      Repo.setKv('daily_step_goal', '$goal');

  /// 读取今日步数状态（带 30 秒写库节流保护）
  static Future<({
    bool supported,
    bool granted,
    int todaySteps,
    int goal,
    double burnedKcal,
  })> getTodaySteps({double weightKg = 65, bool syncWidget = true}) async {
    final goal = await stepGoal();
    final t = today();
    final savedToday =
        (int.tryParse(await Repo.getKv('steps_val_$t') ?? '') ?? 0).clamp(0, 200000);

    try {
      final res = await _ch.invokeMethod<Map>('getStepSensorState');
      if (res != null) {
        final supported = (res['supported'] as bool?) ?? false;
        final granted = (res['granted'] as bool?) ?? true;
        final rawSteps = (res['rawSteps'] as int?) ?? -1;

        if (supported && rawSteps >= 0) {
          final baseDate = await Repo.getKv('steps_base_date');
          var baseRaw = int.tryParse(await Repo.getKv('steps_base_raw') ?? '');

          if (baseDate != t || baseRaw == null || rawSteps < baseRaw) {
            baseRaw = rawSteps - savedToday;
            await Repo.setKv('steps_base_date', t);
            await Repo.setKv('steps_base_raw', '$baseRaw');
          }

          final currentSteps = (rawSteps - baseRaw).clamp(0, 200000);
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final shouldWriteDb = (t != _lastWrittenDate) ||
              (currentSteps != savedToday &&
                  currentSteps != _lastWrittenSteps &&
                  (nowMs - _lastWriteMs >= _writeThrottleMs));

          if (shouldWriteDb) {
            _lastWriteMs = nowMs;
            _lastWrittenSteps = currentSteps;
            _lastWrittenDate = t;
            await Repo.setKv('steps_val_$t', '$currentSteps');
            UsageTelemetryService.instance.trackFeature('step_sync', 'success');
          }
          if (syncWidget && currentSteps != savedToday) {
            WidgetService.sync(fromStepUpdate: true);
          }
          final kcal = Nutrition.calcStepCalories(steps: currentSteps, weightKg: weightKg);
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
          burnedKcal: Nutrition.calcStepCalories(steps: savedToday, weightKg: weightKg),
        );
      }
    } catch (_) {}

    return (
      supported: false,
      granted: false,
      todaySteps: savedToday,
      goal: goal,
      burnedKcal: Nutrition.calcStepCalories(steps: savedToday, weightKg: weightKg),
    );
  }
}
