import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_prefs.dart';
import '../../services/bus_service.dart';
import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

/// 校车时刻表多路线管理与查看页面（v1.3）：
/// - 顶部「当前路线」选择器（默认 BUV · Hai Ba Trung Route）
/// - 支持切换路线、手动创建/编辑自定义路线、选择 .json 文件导入（带严格格式校验）、下载/导出空模板
class BusScheduleScreen extends StatefulWidget {
  const BusScheduleScreen({super.key});

  @override
  State<BusScheduleScreen> createState() => _BusScheduleScreenState();
}

class _BusScheduleScreenState extends State<BusScheduleScreen> {
  List<BusRouteData> _allRoutes = [];
  BusRouteData? _data;
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
    final all = await BusService.loadAllRoutes(forceReload: true);
    final data = await BusService.load();
    final stops = await BusService.allStopNames();
    final fav = await BusService.favoriteStop();
    final en = await BusService.reminderEnabled();
    final mins = await BusService.reminderMinutesBefore();
    if (!mounted) return;
    setState(() {
      _allRoutes = all;
      _data = data;
      _stops = stops;
      _favStop = stops.contains(fav) ? fav : (stops.isNotEmpty ? stops.first : '');
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
    toast(context, '校车站点与提醒已保存');
  }

  Future<void> _switchRoute(BusRouteData r) async {
    await BusService.setActiveRouteId(r.id);
    await _load();
    await ReminderService.syncAlarms();
    if (!mounted) return;
    toast(context, '已切换路线为：${r.name}');
  }

  Future<void> _downloadTemplate() async {
    final jsonStr = BusService.templateJsonString();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bus_route_template.json');
    await file.writeAsString(jsonStr);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '校车路线 JSON 模板 (bus_route_template.json)',
      ),
    );
  }

  Future<void> _exportCurrentRoute() async {
    final d = _data;
    if (d == null) return;
    final jsonStr = const JsonEncoder.withIndent('  ').convert(d.toJson());
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${d.id}.json');
    await file.writeAsString(jsonStr);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '分享校车路线：${d.name}',
      ),
    );
  }

  Future<void> _importFromFile() async {
    final raw = await ReminderService.pickJsonFile();
    if (raw == null || !mounted) return;
    try {
      final imported = await BusService.importRouteFromJsonString(raw, source: 'imported');
      await BusService.setActiveRouteId(imported.id);
      await _load();
      await ReminderService.syncAlarms();
      if (!mounted) return;
      toast(context, '成功导入并启用路线：${imported.name}');
    } on FormatException catch (e) {
      if (!mounted) return;
      _showValidationError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showValidationError('导入失败：$e');
    }
  }

  void _showValidationError(String msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('路线格式校验未通过'),
          ],
        ),
        content: Text(msg),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  void _openRouteSelectorSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route_rounded, color: Color(0xFF2B5B84)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('切换或管理校车路线', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _downloadTemplate();
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('下载模板'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _allRoutes.length,
                itemBuilder: (_, i) {
                  final r = _allRoutes[i];
                  final selected = r.id == _data?.id;
                  return Card(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55)
                        : null,
                    child: ListTile(
                      leading: Icon(
                        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: selected ? const Color(0xFF2B5B84) : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (r.isBuiltin ? const Color(0xFF2B5B84) : const Color(0xFFFF7A22))
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              r.isBuiltin ? '内置' : (r.source == 'imported' ? '已导入' : '自定义'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: r.isBuiltin ? const Color(0xFF2B5B84) : const Color(0xFFFF7A22),
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        [
                          if (r.school.isNotEmpty) r.school,
                          '去程 ${r.outboundStops.length} 站 · 回程 ${r.inboundStops.length} 站',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: r.isBuiltin
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '编辑路线',
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _openCustomRouteDialog(existing: r);
                                  },
                                ),
                                IconButton(
                                  tooltip: '删除路线',
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    if (await confirm(context, '确定删除路线「${r.name}」吗？')) {
                                      await BusService.deleteUserRoute(r.id);
                                      await _load();
                                      await ReminderService.syncAlarms();
                                    }
                                  },
                                ),
                              ],
                            ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _switchRoute(r);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openCustomRouteDialog();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('手动创建路线'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _importFromFile();
                    },
                    icon: const Icon(Icons.file_open_rounded),
                    label: const Text('导入 JSON 文件'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCustomRouteDialog({BusRouteData? existing}) async {
    final saved = await showDialog<BusRouteData>(
      context: context,
      builder: (_) => _CustomRouteEditDialog(existing: existing),
    );
    if (saved != null) {
      try {
        await BusService.saveUserRoute(saved);
        await BusService.setActiveRouteId(saved.id);
        await _load();
        await ReminderService.syncAlarms();
        if (!mounted) return;
        toast(context, '已保存并切换到路线：${saved.name}');
      } on FormatException catch (e) {
        if (!mounted) return;
        _showValidationError(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final prefs = AppPrefsController.instance;
    final slotCount = d == null || d.outboundStops.isEmpty ? 5 : d.outboundStops.first.times.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.directions_bus_rounded, color: Color(0xFF2B5B84)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                prefs.tr('校车时刻表', 'Bus Schedule'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '导出/分享当前路线 JSON',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _exportCurrentRoute,
          ),
          IconButton(
            tooltip: '下载空模板 JSON',
            icon: const Icon(Icons.download_rounded),
            onPressed: _downloadTemplate,
          ),
        ],
      ),
      body: _loading || d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
              children: [
                // 2.1 路线选择器卡片
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  child: ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B5B84).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.alt_route_rounded, color: Color(0xFF2B5B84)),
                    ),
                    title: Text(
                      '当前路线：${prefs.isEn ? d.nameEn : d.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${d.isBuiltin ? '内置路线' : '自定义路线'}${d.school.isNotEmpty ? ' · ${d.school}' : ''}（共 ${_allRoutes.length} 条可用）',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: FilledButton.tonalIcon(
                      onPressed: _openRouteSelectorSheet,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: Text(prefs.tr('切换/导入', 'Switch')),
                    ),
                    onTap: _openRouteSelectorSheet,
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Color(0xFFFF7A22)),
                            const SizedBox(width: 6),
                            Text(
                              prefs.tr('我的常用站点与到站提醒', 'Favorite Stop & Reminder'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_stops.isNotEmpty)
                          DropdownButtonFormField<String>(
                            key: ValueKey('stop-${d.id}-$_favStop'),
                            initialValue: _stops.contains(_favStop) ? _favStop : _stops.first,
                            decoration: InputDecoration(
                              labelText: prefs.tr('选择常用上/下车站点（首页显示该站倒计时）', 'Select Favorite Stop'),
                              prefixIcon: const Icon(Icons.place_rounded, color: Color(0xFF2B5B84)),
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
                          title: Text(prefs.tr('校车到站前手机震动提醒（仅周一至周五）', 'Bus Arrival Vibration Reminder (Mon-Fri)')),
                          subtitle: Text(prefs.tr('周末自动静音不打扰', 'Muted automatically on weekends')),
                          value: _remEnabled,
                          onChanged: (v) {
                            setState(() => _remEnabled = v);
                            _savePrefs();
                          },
                        ),
                        if (_remEnabled)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(prefs.tr('提前多久提醒', 'Remind Before')),
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
                _tableCard(d.outboundStops, slotCount),
                SectionTitle(d.inboundTitle, icon: Icons.arrow_circle_left_rounded, iconColor: const Color(0xFFFF7A22)),
                _tableCard(d.inboundStops, d.inboundStops.isEmpty ? slotCount : d.inboundStops.first.times.length),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline_rounded, color: Colors.teal),
                    title: const Text('多路线与模板分享说明', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(
                      '支持点击右上角下载空 JSON 模板或分享当前路线给同学。内置 BUV 路线源于 assets/bus_schedule.json，自定义路线保存在应用数据目录 routes/ 下。',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tableCard(List<BusStopSchedule> stops, int slotCount) {
    final cs = Theme.of(context).colorScheme;
    final cols = slotCount.clamp(1, 10);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 42,
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('站点', style: TextStyle(fontWeight: FontWeight.bold))),
            for (var i = 1; i <= cols; i++)
              DataColumn(label: Text('Slot $i', style: const TextStyle(fontWeight: FontWeight.bold))),
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
                for (var i = 0; i < cols; i++)
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

/// 手动创建 / 编辑自定义校车路线弹窗
class _CustomRouteEditDialog extends StatefulWidget {
  final BusRouteData? existing;
  const _CustomRouteEditDialog({this.existing});

  @override
  State<_CustomRouteEditDialog> createState() => _CustomRouteEditDialogState();
}

class _CustomRouteEditDialogState extends State<_CustomRouteEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _school;
  late final TextEditingController _outboundText;
  late final TextEditingController _inboundText;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _school = TextEditingController(text: e?.school ?? '');
    _outboundText = TextEditingController(
      text: e == null
          ? 'CITY CENTER: 07:30, 09:30, 13:00\nSUBWAY STATION: 07:45, 09:45, 13:15\nMAIN CAMPUS: 08:15, 10:15, 13:45'
          : e.outboundStops.map((s) => '${s.name}: ${s.times.join(', ')}').join('\n'),
    );
    _inboundText = TextEditingController(
      text: e == null
          ? 'MAIN CAMPUS: 12:00, 15:30, 17:30\nSUBWAY STATION: 12:30, 16:00, 18:00\nCITY CENTER: 12:45, 16:15, 18:15'
          : e.inboundStops.map((s) => '${s.name}: ${s.times.join(', ')}').join('\n'),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    _outboundText.dispose();
    _inboundText.dispose();
    super.dispose();
  }

  List<BusStopSchedule> _parseLines(String raw) {
    final out = <BusStopSchedule>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final idx = t.indexOf(':');
      if (idx <= 0) {
        final idxCn = t.indexOf('：');
        if (idxCn <= 0) continue;
        final name = t.substring(0, idxCn).trim();
        final times = t
            .substring(idxCn + 1)
            .split(RegExp(r'[,，\s]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        out.add(BusStopSchedule(name: name, times: times));
      } else {
        final name = t.substring(0, idx).trim();
        final times = t
            .substring(idx + 1)
            .split(RegExp(r'[,，\s]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        out.add(BusStopSchedule(name: name, times: times));
      }
    }
    return out;
  }

  void _submit() {
    final route = BusRouteData(
      id: widget.existing?.id ?? 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      nameEn: _name.text.trim(),
      school: _school.text.trim(),
      source: 'custom',
      outboundTitle: '去程 (Outbound)',
      outboundStops: _parseLines(_outboundText.text),
      inboundTitle: '回程 (Inbound)',
      inboundStops: _parseLines(_inboundText.text),
    );
    final err = BusService.validateRouteMap(route.toJson());
    if (err != null) {
      toast(context, err);
      return;
    }
    Navigator.pop(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '手动创建校车路线' : '编辑校车路线'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '路线名称 *',
                hintText: '如：BUV · Ecopark Route',
                prefixIcon: Icon(Icons.alt_route_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _school,
              decoration: const InputDecoration(
                labelText: '学校名称（可选）',
                prefixIcon: Icon(Icons.school_rounded),
              ),
            ),
            const SizedBox(height: 12),
            const Text('去程站点与时刻（每行一站，格式：站点名: 07:30, 09:30）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _outboundText,
              maxLines: 4,
              decoration: const InputDecoration(),
            ),
            const SizedBox(height: 12),
            const Text('回程站点与时刻（每行一站，格式：站点名: 12:00, 17:30）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _inboundText,
              maxLines: 4,
              decoration: const InputDecoration(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('校验并保存'),
        ),
      ],
    );
  }
}
