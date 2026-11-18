import 'package:flutter/material.dart';

import '../../services/battery_probe_service.dart';
import '../../services/widget_service.dart';
import '../../widgets/common.dart';

/// 耗电与性能诊断页（v2.0）：
/// - 展示最近 24 小时及近 7 天滚动统计：前台时长、后台时长、计时器活跃时长、GPS 调用次数、数据库写入次数、小组件刷新次数
/// - 数据存于 Repo 的 kv 表（battery_probe_7d_v1），滚动保留 7 天
class BatteryDiagnosticsScreen extends StatefulWidget {
  const BatteryDiagnosticsScreen({super.key});

  @override
  State<BatteryDiagnosticsScreen> createState() => _BatteryDiagnosticsScreenState();
}

class _BatteryDiagnosticsScreenState extends State<BatteryDiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  List<DayBatteryMetrics> _days = [];
  bool _loading = true;
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _load();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool animateSpin = false}) async {
    if (animateSpin && !MediaQuery.disableAnimationsOf(context)) {
      _spinCtrl.forward(from: 0);
    }
    final list = await BatteryProbeService.instance.getRolling7Days();
    if (!mounted) return;
    setState(() {
      _days = list;
      _loading = false;
    });
  }

  String _fmtDuration(int totalSeconds) {
    final secs = totalSeconds.clamp(0, 8640000);
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final teal = AppColors.teal(context);
    final primary = AppColors.primary(context);
    final todayMetrics = _days.isNotEmpty ? _days.first : DayBatteryMetrics(date: '--');
    final activeTimers = BatteryProbeService.instance.activeTimerCount;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, teal),
                borderRadius: AppRadius.bSm,
              ),
              child: Icon(Icons.battery_charging_full_rounded, color: teal, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l.batteryDiagTitle,
                style: AppTypography.pageTitle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            icon: RotationTransition(
              turns: _spinCtrl,
              child: const Icon(Icons.refresh_rounded),
            ),
            onPressed: () => _load(animateSpin: true),
          ),
          TextButton.icon(
            onPressed: () async {
              if (await confirm(context, l.batteryDiagResetConfirm, ok: l.commonConfirm)) {
                await BatteryProbeService.instance.resetStats();
                await _load(animateSpin: true);
                if (context.mounted) toast(context, l.batteryDiagResetToast);
              }
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: Text(l.batteryDiagResetBtn),
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
                  backgroundColor: AppColors.softBg(context, teal, lightAlpha: 0.08, darkAlpha: 0.14),
                  borderColor: AppColors.softBorder(context, teal),
                  padding: AppSpacing.cardCompactPadding,
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.softBg(context, teal, lightAlpha: 0.16, darkAlpha: 0.24),
                          borderRadius: AppRadius.bMd,
                        ),
                        child: Icon(Icons.speed_rounded, color: teal, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.batteryDiagSummaryTitle, style: AppTypography.cardTitle(context)),
                            const SizedBox(height: 2),
                            Text(
                              l.batteryDiagActiveTimers(activeTimers),
                              style: AppTypography.bodySecondary(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildTodayGrid(todayMetrics),
                SectionTitle(
                  l.batteryDiagHistoryTitle,
                  icon: Icons.history_rounded,
                  iconColor: primary,
                ),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < _days.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.softBg(context, primary),
                                  borderRadius: AppRadius.bMd,
                                ),
                                child: Icon(
                                  Icons.calendar_today_rounded,
                                  color: primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_days[i].date, style: AppTypography.cardTitle(context)),
                                    const SizedBox(height: 4),
                                    Text(
                                      l.batteryDiagDaySub(
                                        _fmtDuration(_days[i].foregroundSec),
                                        _fmtDuration(_days[i].backgroundSec),
                                        _fmtDuration(_days[i].timerActiveSec),
                                        _days[i].gpsCalls,
                                        _days[i].dbWrites,
                                        _days[i].widgetRefreshes,
                                      ),
                                      style: AppTypography.bodySecondary(context),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SectionTitle(
                  l.batteryDiagTipTitle,
                  icon: Icons.eco_rounded,
                  iconColor: teal,
                ),
                SurfaceCard(
                  padding: AppSpacing.cardPadding,
                  child: Text(
                    l.batteryDiagTipSub,
                    style: AppTypography.body(context).copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTodayGrid(DayBatteryMetrics m) {
    final l = context.l10n;
    Widget tile(IconData icon, Color color, String label, String value) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle(context),
            borderRadius: AppRadius.bLg,
          ),
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, color),
                  borderRadius: AppRadius.bSm,
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: AppTypography.metricMedium(context)),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.caption(context).copyWith(fontSize: 10.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              tile(
                Icons.phone_android_rounded,
                AppColors.primary(context),
                l.batteryDiagFgTime,
                _fmtDuration(m.foregroundSec),
              ),
              tile(
                Icons.bedtime_rounded,
                AppColors.info(context),
                l.batteryDiagBgTime,
                _fmtDuration(m.backgroundSec),
              ),
              tile(
                Icons.timer_rounded,
                AppColors.accent(context),
                l.batteryDiagTimerTime,
                _fmtDuration(m.timerActiveSec),
              ),
            ],
          ),
          Row(
            children: [
              tile(
                Icons.my_location_rounded,
                AppColors.teal(context),
                l.batteryDiagGpsCalls,
                '${m.gpsCalls}',
              ),
              tile(
                Icons.storage_rounded,
                AppColors.moduleSchedule(context),
                l.batteryDiagDbWrites,
                '${m.dbWrites}',
              ),
              tile(
                Icons.widgets_rounded,
                AppColors.moduleAi(context),
                l.batteryDiagWidgetSyncs,
                '${m.widgetRefreshes}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 弹出「把小组件添加到桌面」引导弹窗（v2.0 统一样式，支持一键调起系统 requestPinAppWidget）
void showAddHomeWidgetGuideDialog(BuildContext context) {
  final l = context.l10n;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final primary = AppColors.primary(ctx);
      return Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(ctx, primary),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(Icons.widgets_rounded, color: primary, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(l.widgetGuideHeader, style: AppTypography.sectionTitle(ctx)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l.widgetGuideDesc, style: AppTypography.body(ctx)),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: AppSpacing.cardCompactPadding,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle(ctx),
                borderRadius: AppRadius.bLg,
                border: Border.all(color: AppColors.border(ctx)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.widgetGuideStep1, style: AppTypography.body(ctx).copyWith(fontSize: 13)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(l.widgetGuideStep2, style: AppTypography.body(ctx).copyWith(fontSize: 13)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(l.widgetGuideStep3, style: AppTypography.body(ctx).copyWith(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await WidgetService.requestPinToHomeScreen();
                if (!context.mounted) return;
                toast(context, ok ? l.widgetGuidePinSuccess : l.widgetGuidePinFallback);
              },
              icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
              label: Text(l.widgetGuidePinBtn),
            ),
          ],
        ),
      );
    },
  );
}
