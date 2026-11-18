import 'package:flutter/material.dart';

import '../../services/battery_probe_service.dart';
import '../../services/widget_service.dart';
import '../../widgets/common.dart';

/// 耗电与性能诊断页（v1.6 P0）：
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
    if (animateSpin) {
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
    final todayMetrics = _days.isNotEmpty ? _days.first : DayBatteryMetrics(date: '--');
    final activeTimers = BatteryProbeService.instance.activeTimerCount;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.battery_charging_full_rounded, color: Color(0xFF26A69A)),
            const SizedBox(width: 8),
            Expanded(child: Text(l.batteryDiagTitle, overflow: TextOverflow.ellipsis)),
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
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l.batteryDiagResetBtn),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: const Color(0xFF26A69A).withValues(alpha: 0.14),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x2226A69A),
                      child: Icon(Icons.speed_rounded, color: Color(0xFF26A69A)),
                    ),
                    title: Text(
                      l.batteryDiagSummaryTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(l.batteryDiagActiveTimers(activeTimers)),
                  ),
                ),
                const SizedBox(height: 6),
                _buildTodayGrid(todayMetrics),
                SectionTitle(
                  l.batteryDiagHistoryTitle,
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFF2B5B84),
                ),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < _days.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2B5B84).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.calendar_today_rounded, color: Color(0xFF2B5B84), size: 18),
                          ),
                          title: Text(
                            _days[i].date,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l.batteryDiagDaySub(
                                _fmtDuration(_days[i].foregroundSec),
                                _fmtDuration(_days[i].backgroundSec),
                                _fmtDuration(_days[i].timerActiveSec),
                                _days[i].gpsCalls,
                                _days[i].dbWrites,
                                _days[i].widgetRefreshes,
                              ),
                              style: const TextStyle(fontSize: 12, height: 1.4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SectionTitle(
                  l.batteryDiagTipTitle,
                  icon: Icons.eco_rounded,
                  iconColor: const Color(0xFF26A69A),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      l.batteryDiagTipSub,
                      style: const TextStyle(fontSize: 12.5, height: 1.55),
                    ),
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
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                tile(Icons.phone_android_rounded, const Color(0xFF2B5B84), l.batteryDiagFgTime, _fmtDuration(m.foregroundSec)),
                tile(Icons.bedtime_rounded, const Color(0xFF5C6BC0), l.batteryDiagBgTime, _fmtDuration(m.backgroundSec)),
                tile(Icons.timer_rounded, const Color(0xFFFF7A22), l.batteryDiagTimerTime, _fmtDuration(m.timerActiveSec)),
              ],
            ),
            Row(
              children: [
                tile(Icons.my_location_rounded, const Color(0xFF26A69A), l.batteryDiagGpsCalls, '${m.gpsCalls}'),
                tile(Icons.storage_rounded, const Color(0xFF42A5F5), l.batteryDiagDbWrites, '${m.dbWrites}'),
                tile(Icons.widgets_rounded, const Color(0xFFAB47BC), l.batteryDiagWidgetSyncs, '${m.widgetRefreshes}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出「把小组件添加到桌面」引导弹窗（支持一键调起系统 requestPinAppWidget）
void showAddHomeWidgetGuideDialog(BuildContext context) {
  final l = context.l10n;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B5B84).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.widgets_rounded, color: Color(0xFF2B5B84), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.widgetGuideHeader,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l.widgetGuideDesc, style: const TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.widgetGuideStep1, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                const SizedBox(height: 4),
                Text(l.widgetGuideStep2, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                const SizedBox(height: 4),
                Text(l.widgetGuideStep3, style: const TextStyle(fontSize: 12.5, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await WidgetService.requestPinToHomeScreen();
              if (!context.mounted) return;
              toast(context, ok ? l.widgetGuidePinSuccess : l.widgetGuidePinFallback);
            },
            icon: const Icon(Icons.add_to_home_screen_rounded),
            label: Text(l.widgetGuidePinBtn),
          ),
        ],
      ),
    ),
  );
}
