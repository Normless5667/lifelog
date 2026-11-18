import 'package:flutter/material.dart';

import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

/// 通知诊断页：显示当前通知权限状态、渠道重要性、震动/声音开关、是否被系统降级，
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
  String _channelName = 'course_reminders_v2';
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

  String _importanceLabel(BuildContext context, int imp) {
    final l = context.l10n;
    switch (imp) {
      case 0:
        return l.diagImp0;
      case 1:
        return l.diagImp1;
      case 2:
        return l.diagImp2;
      case 3:
        return l.diagImp3;
      case 4:
      case 5:
        return l.diagImpHigh(imp);
      default:
        return '$imp';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final allGood = _enabled && _importance >= 4 && _vibrate && _exactAlarm;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.health_and_safety_rounded, color: Color(0xFF2B5B84)),
            const SizedBox(width: 8),
            Expanded(child: Text(l.diagTitle, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.diagRefreshTooltip,
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
                                allGood ? l.diagStatusGood : l.diagStatusWarn,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l.diagDeviceChannelSub(_device, _channelName, _channelId),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SectionTitle(l.diagSectionPermissions, icon: Icons.fact_check_rounded),
                Card(
                  child: Column(
                    children: [
                      _diagRow(
                        ok: _enabled,
                        title: l.diagAppNotifTitle,
                        subtitle: _enabled ? l.diagAppNotifOn : l.diagAppNotifOff,
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _importance >= 4,
                        title: l.diagImportanceTitle,
                        subtitle: _importanceLabel(context, _importance),
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _vibrate,
                        title: l.diagVibrateTitle,
                        subtitle: _vibrate ? l.diagVibrateOn : l.diagVibrateOff,
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _sound,
                        title: l.diagSoundTitle,
                        subtitle: _sound ? l.diagSoundOn : l.diagSoundOff,
                      ),
                      const Divider(height: 1),
                      _diagRow(
                        ok: _exactAlarm,
                        title: l.diagExactAlarmTitle,
                        subtitle: _exactAlarm ? l.diagExactAlarmOn : l.diagExactAlarmOff,
                      ),
                    ],
                  ),
                ),
                SectionTitle(l.diagSectionColorOs, icon: Icons.build_circle_rounded),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.diagColorOsGuide,
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () async {
                            await ReminderService.openAppNotificationSettings();
                            await Future<void>.delayed(const Duration(seconds: 1));
                            _refresh();
                          },
                          icon: const Icon(Icons.notifications_active_rounded),
                          label: Text(l.diagBtn1AppNotif),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ReminderService.openNotificationSettings();
                            await Future<void>.delayed(const Duration(seconds: 1));
                            _refresh();
                          },
                          icon: const Icon(Icons.tune_rounded),
                          label: Text(l.diagBtn2Channel),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await ReminderService.testNotification();
                            if (context.mounted) {
                              toast(context, l.diagTestSentToast);
                            }
                          },
                          icon: const Icon(Icons.vibration_rounded),
                          label: Text(l.diagBtn3Test),
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
