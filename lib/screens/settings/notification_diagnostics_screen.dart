import 'package:flutter/material.dart';

import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

/// 通知诊断页（P0）：显示当前通知权限状态、渠道重要性、震动/声音开关、是否被 ColorOS 等系统降级，
/// 并提供一键跳转应用通知设置与渠道设置的按钮。
class NotificationDiagnosticsScreen extends StatefulWidget {
  const NotificationDiagnosticsScreen({super.key});

  @override
  State<NotificationDiagnosticsScreen> createState() => _NotificationDiagnosticsScreenState();
}

class _NotificationDiagnosticsScreenState extends State<NotificationDiagnosticsScreen> {
  bool _loading = true;
  bool _enabled = true;
  int _importance = 4;
  bool _vibrate = true;
  bool _sound = true;
  bool _exactAlarm = true;
  String _channelId = 'course_reminders_v2';
  String _channelName = '生活助手·强提醒通知';
  String _device = 'Android';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final s = await ReminderService.checkNotificationStatus();
    if (!mounted) return;
    setState(() {
      _enabled = s.enabled;
      _importance = s.importance;
      _vibrate = s.vibrate;
      _sound = s.sound;
      _exactAlarm = s.exactAlarm;
      _channelId = s.channelId;
      _channelName = s.channelName;
      _device = s.device;
      _loading = false;
    });
  }

  String _importanceLabel(int imp) {
    switch (imp) {
      case 0:
        return '0 - 已关闭 (NONE)';
      case 1:
        return '1 - 极低 (MIN，无声无横幅)';
      case 2:
        return '2 - 低 (LOW，被降级为静默/其他通知)';
      case 3:
        return '3 - 默认 (DEFAULT，可能无横幅弹窗)';
      case 4:
      case 5:
        return '$imp - 高/最高 (HIGH/MAX，正常弹出横幅+震动)';
      default:
        return '$imp';
    }
  }

  @override
  Widget build(BuildContext context) {
    final allGood = _enabled && _importance >= 4 && _vibrate && _exactAlarm;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.health_and_safety_rounded, color: Color(0xFF2B5B84)),
            SizedBox(width: 8),
            Text('通知与震动诊断'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '重新检测',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: allGood
                      ? const Color(0xFF26A69A).withValues(alpha: 0.14)
                      : const Color(0xFFFF7A22).withValues(alpha: 0.16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          allGood ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                          size: 38,
                          color: allGood ? const Color(0xFF26A69A) : const Color(0xFFFF7A22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                allGood ? '当前通知与强震动状态正常' : '检测到通知或震动可能被系统限制',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '设备：$_device\n渠道：$_channelName ($_channelId)',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('各项权限与系统分级状态', icon: Icons.fact_check_rounded),
                Card(
                  child: Column(
                    children: [
                      _diagRow(
                        ok: _enabled,
                        title: '应用通知总开关 (areNotificationsEnabled)',
                        subtitle: _enabled ? '已开启' : '被关闭！将无法收到任何上课或校车提醒',
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _importance >= 4,
                        title: '通知渠道重要性 (Channel Importance)',
                        subtitle: _importanceLabel(_importance),
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _vibrate,
                        title: '渠道震动许可 (shouldVibrate)',
                        subtitle: _vibrate ? '已允许震动（+ 硬件闹钟震动双保险）' : '渠道震动被系统关闭，请点下方按钮开启',
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _sound,
                        title: '通知提示音 (Sound URI)',
                        subtitle: _sound ? '已配置提示音' : '静音状态',
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _exactAlarm,
                        title: '精确闹钟权限 (canScheduleExactAlarms)',
                        subtitle: _exactAlarm ? '已授权准时触发' : '未授权精确闹钟，提醒可能延迟',
                      ),
                    ],
                  ),
                ),
                const SectionTitle('OPPO / ColorOS 专属修复操作', icon: Icons.build_circle_rounded),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '如果在 OPPO / Find X8 等机型上通知不弹横幅或不震动，请点击下面两个按钮，把「生活助手」设为允许通知，并将「生活助手·强提醒通知」设为【重要通知】且打开【横幅】与【震动】：',
                          style: TextStyle(fontSize: 12, height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () async {
                            await ReminderService.openAppNotificationSettings();
                            await Future<void>.delayed(const Duration(seconds: 1));
                            _refresh();
                          },
                          icon: const Icon(Icons.notifications_active_rounded),
                          label: const Text('1. 一键打开「生活助手」应用通知设置'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ReminderService.openNotificationSettings();
                            await Future<void>.delayed(const Duration(seconds: 1));
                            _refresh();
                          },
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('2. 一键打开「强提醒通知渠道」详细设置'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await ReminderService.testNotification();
                            if (context.mounted) {
                              toast(context, '已发送测试强提醒（含闹钟级震动 + 声音 + 横幅）');
                            }
                          },
                          icon: const Icon(Icons.vibration_rounded),
                          label: const Text('3. 立即发送一条全屏横幅+强震动测试通知'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _diagRow({required bool ok, required String title, required String subtitle}) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (ok ? const Color(0xFF26A69A) : const Color(0xFFEF5350)).withValues(alpha: 0.15),
        child: Icon(
          ok ? Icons.check_rounded : Icons.priority_high_rounded,
          color: ok ? const Color(0xFF26A69A) : const Color(0xFFEF5350),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }
}
