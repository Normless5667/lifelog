import 'package:flutter/material.dart';

import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

/// 通知诊断页（v2.0）：显示当前通知权限状态、渠道重要性、震动/声音开关、是否被系统降级，
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
    final primary = AppColors.primary(context);
    final teal = AppColors.teal(context);
    final accent = AppColors.accent(context);
    final allGood = _enabled && _importance >= 4 && _vibrate && _exactAlarm;
    final bannerColor = allGood ? teal : accent;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, primary),
                borderRadius: AppRadius.bSm,
              ),
              child: Icon(Icons.health_and_safety_rounded, color: primary, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l.diagTitle,
                style: AppTypography.pageTitle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                SurfaceCard(
                  backgroundColor: AppColors.softBg(context, bannerColor, lightAlpha: 0.10, darkAlpha: 0.16),
                  borderColor: AppColors.softBorder(context, bannerColor),
                  padding: AppSpacing.cardPadding,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.softBg(context, bannerColor, lightAlpha: 0.18, darkAlpha: 0.25),
                          borderRadius: AppRadius.bMd,
                        ),
                        child: Icon(
                          allGood ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                          size: 24,
                          color: bannerColor,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              allGood ? l.diagStatusGood : l.diagStatusWarn,
                              style: AppTypography.cardTitle(context),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              l.diagDeviceChannelSub(_device, _channelName, _channelId),
                              style: AppTypography.bodySecondary(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SectionTitle(l.diagSectionPermissions, icon: Icons.fact_check_rounded),
                SurfaceCard(
                  padding: EdgeInsets.zero,
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
                SectionTitle(
                  l.diagSectionColorOs,
                  icon: Icons.build_circle_rounded,
                  iconColor: accent,
                ),
                SurfaceCard(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.diagColorOsGuide, style: AppTypography.body(context).copyWith(fontSize: 13)),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () async {
                          await ReminderService.openAppNotificationSettings();
                          await Future<void>.delayed(const Duration(seconds: 1));
                          _refresh();
                        },
                        icon: const Icon(Icons.notifications_active_rounded, size: 18),
                        label: Text(l.diagBtn1AppNotif),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ReminderService.openNotificationSettings();
                          await Future<void>.delayed(const Duration(seconds: 1));
                          _refresh();
                        },
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: Text(l.diagBtn2Channel),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await ReminderService.testNotification();
                          if (context.mounted) {
                            toast(context, l.diagTestSentToast);
                          }
                        },
                        icon: const Icon(Icons.vibration_rounded, size: 18),
                        label: Text(l.diagBtn3Test),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _diagRow({required bool ok, required String title, required String subtitle}) {
    final rowColor = ok ? AppColors.teal(context) : AppColors.danger(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, rowColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(
              ok ? Icons.check_rounded : Icons.priority_high_rounded,
              color: rowColor,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.subtitle(context)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.bodySecondary(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
