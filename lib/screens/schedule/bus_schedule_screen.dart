import 'package:flutter/material.dart';

import '../../services/bus_service.dart';
import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

/// 校车时刻表完整页面（Hai Ba Trung Route 去程 & 回程 5 时段全表 + 常用站点选择 + 到站前 N 分钟提醒设置）
class BusScheduleScreen extends StatefulWidget {
  const BusScheduleScreen({super.key});

  @override
  State<BusScheduleScreen> createState() => _BusScheduleScreenState();
}

class _BusScheduleScreenState extends State<BusScheduleScreen> {
  BusScheduleData? _data;
  List<String> _stops = [];
  String _favStop = 'TIMES CITY';
  bool _remEnabled = true;
  int _remMins = 10;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await BusService.load();
    final stops = await BusService.allStopNames();
    final fav = await BusService.favoriteStop();
    final en = await BusService.reminderEnabled();
    final mins = await BusService.reminderMinutesBefore();
    if (!mounted) return;
    setState(() {
      _data = data;
      _stops = stops;
      _favStop = stops.contains(fav) ? fav : stops.first;
      _remEnabled = en;
      _remMins = mins;
      _loading = false;
    });
  }

  Future<void> _savePrefs() async {
    await BusService.setFavoriteStop(_favStop);
    await BusService.setReminderEnabled(_remEnabled);
    await BusService.setReminderMinutesBefore(_remMins);
    await ReminderService.syncAlarms();
    if (!mounted) return;
    toast(context, '校车站点与提醒已保存（仅周一至周五提醒）');
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.directions_bus_rounded, color: Color(0xFF2B5B84)),
            SizedBox(width: 8),
            Text('校车时刻表 (Hai Ba Trung)'),
          ],
        ),
      ),
      body: _loading || d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.star_rounded, color: Color(0xFFFF7A22)),
                            SizedBox(width: 6),
                            Text('我的常用站点与到站提醒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _favStop,
                          decoration: const InputDecoration(
                            labelText: '选择常用上/下车站点（首页将显示该站倒计时）',
                            prefixIcon: Icon(Icons.place_rounded, color: Color(0xFF2B5B84)),
                          ),
                          items: _stops
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _favStop = v);
                            _savePrefs();
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('校车到站前手机震动提醒（仅周一至周五）'),
                          subtitle: const Text('周末自动静音不打扰'),
                          value: _remEnabled,
                          onChanged: (v) {
                            setState(() => _remEnabled = v);
                            _savePrefs();
                          },
                        ),
                        if (_remEnabled)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('提前多久提醒'),
                            trailing: DropdownButton<int>(
                              value: _remMins,
                              items: const [
                                DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                                DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
                                DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _remMins = v);
                                _savePrefs();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SectionTitle(d.outboundTitle, icon: Icons.arrow_circle_right_rounded, iconColor: const Color(0xFF2B5B84)),
                _tableCard(d.outboundStops),
                SectionTitle(d.inboundTitle, icon: Icons.arrow_circle_left_rounded, iconColor: const Color(0xFFFF7A22)),
                _tableCard(d.inboundStops),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline_rounded, color: Colors.teal),
                    title: const Text('校车时刻表维护说明', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(
                      '数据源位于工程 assets/bus_schedule.json（有效期 ${d.validPeriod}）。${d.note}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tableCard(List<BusStopSchedule> stops) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 42,
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('站点', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Slot 1', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Slot 2', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Slot 3', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Slot 4', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Slot 5', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: stops.map((s) {
            final isFav = s.name.contains(_favStop);
            return DataRow(
              color: isFav ? WidgetStatePropertyAll(cs.primaryContainer.withValues(alpha: 0.45)) : null,
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFav) const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFF7A22)),
                      if (isFav) const SizedBox(width: 4),
                      Text(
                        s.name,
                        style: TextStyle(
                          fontWeight: isFav ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < 5; i++)
                  DataCell(
                    Text(
                      i < s.times.length ? s.times[i] : '-',
                      style: TextStyle(
                        fontWeight: isFav ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
