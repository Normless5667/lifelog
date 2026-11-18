import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_prefs.dart';
import '../../services/bus_service.dart';
import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

enum _SlotState {
  imminent, // ≤ 5 分钟：红/橙 + 呼吸脉冲
  soon, // 6-15 分钟：琥珀色
  upcoming, // > 15 分钟：蓝色
  departed, // 已发车：灰色半透明 + 划线沉底
  endedToday, // 今日全部已结束：灰色沉底
}

class _SlotBoardItem {
  final int slotIndex; // 0-based
  final String favTimeStr;
  final DateTime favTargetTime;
  final DateTime prevSlotTime;
  final DateTime firstStopTime;
  final DateTime lastStopTime;
  final Duration remain;
  final _SlotState state;
  final bool enRoute; // 当前时刻是否已从首站发车且未到末站

  const _SlotBoardItem({
    required this.slotIndex,
    required this.favTimeStr,
    required this.favTargetTime,
    required this.prevSlotTime,
    required this.firstStopTime,
    required this.lastStopTime,
    required this.remain,
    required this.state,
    required this.enRoute,
  });
}

/// 校车时刻表 v1.4：机场航班屏动态看板 + 多路线管理
/// - 卡片流按「距离现在的时间」升序排列，最近一班排最上，已发车自动沉底置灰
/// - 五档状态色：即将到站(≤5min 红橙+微呼吸动画)、快到了(6-15min 琥珀)、待发车(>15min 蓝)、已发车(灰+划线)、今日已结束(灰)
/// - 实时秒级倒计时：Timer.periodic(1s) + targetTime.difference(DateTime.now()) 绝对时间差，dispose 严格销毁
/// - 上一班 → 下一班水平区间进度条 + 当前时刻圆点标记
/// - 常用站高亮（底色 + 「← 你的常用站」标签）+ 顶部去程/回程 SegmentedButton（按当前时间智能默认）
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

  /// 去程(false) / 回程(true)，按当前时间自动推荐（14:00 前默认去程，14:00 后默认回程）
  late bool _isInbound;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _pulse = false;
  bool _showSettingsPanel = false;

  @override
  void initState() {
    super.initState();
    _isInbound = DateTime.now().hour >= 14;
    _load();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        _pulse = !_pulse;
      });
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clockTimer = null;
    super.dispose();
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
      _now = DateTime.now();
      _loading = false;
    });
  }

  Future<void> _savePrefs() async {
    await BusService.setFavoriteStop(_favStop);
    await BusService.setReminderEnabled(_remEnabled);
    await BusService.setReminderMinutesBefore(_remMins);
    await ReminderService.syncAlarms();
    if (!mounted) return;
    toast(context, '已更新常用站为 $_favStop');
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

  static String _cleanStopName(String s) =>
      s.replaceAll('（到校）', '').replaceAll('（发车）', '').replaceAll('（终点）', '').trim();

  DateTime _parseTodayTime(String hhmm, DateTime refDay) {
    final parts = hhmm.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return DateTime(refDay.year, refDay.month, refDay.day, h, m);
    }
    return refDay;
  }

  /// 构建机场航班屏式的排序班次列表（即将发车的按时间升序在最上，已发车的沉底）
  List<_SlotBoardItem> _buildSortedSlotItems(List<BusStopSchedule> stops, DateTime now) {
    if (stops.isEmpty || stops.first.times.isEmpty) return const [];
    final slotCount = stops.first.times.length;

    // 匹配常用站（若当前方向没有该站则取第一站作为参考）
    final favStopObj = stops.firstWhere(
      (s) => _cleanStopName(s.name) == _favStop || s.name.contains(_favStop),
      orElse: () => stops.first,
    );

    final rawItems = <({
      int slotIndex,
      String favTimeStr,
      DateTime favTargetTime,
      DateTime prevSlotTime,
      DateTime firstStopTime,
      DateTime lastStopTime,
      Duration remain,
      bool enRoute,
    })>[];

    DateTime? lastTarget;
    for (var i = 0; i < slotCount; i++) {
      final favStr = i < favStopObj.times.length ? favStopObj.times[i] : favStopObj.times.last;
      final firstStr = i < stops.first.times.length ? stops.first.times[i] : favStr;
      final lastStr = i < stops.last.times.length ? stops.last.times[i] : favStr;

      final favTarget = _parseTodayTime(favStr, now);
      final firstTime = _parseTodayTime(firstStr, now);
      final lastTime = _parseTodayTime(lastStr, now);
      final prevTime = lastTarget ?? favTarget.subtract(const Duration(minutes: 45));
      lastTarget = favTarget;

      // 严格使用 targetTime.difference(DateTime.now()) 计算倒计时
      final remain = favTarget.difference(now);
      final enRoute = !now.isBefore(firstTime) && now.isBefore(lastTime);

      rawItems.add((
        slotIndex: i,
        favTimeStr: favStr,
        favTargetTime: favTarget,
        prevSlotTime: prevTime,
        firstStopTime: firstTime,
        lastStopTime: lastTime,
        remain: remain,
        enRoute: enRoute,
      ));
    }

    final hasAnyUpcoming = rawItems.any((e) => !e.remain.isNegative);
    final upcoming = <_SlotBoardItem>[];
    final departed = <_SlotBoardItem>[];

    for (final item in rawItems) {
      if (!item.remain.isNegative) {
        final secs = item.remain.inSeconds;
        final state = secs <= 300
            ? _SlotState.imminent
            : (secs <= 900 ? _SlotState.soon : _SlotState.upcoming);
        upcoming.add(_SlotBoardItem(
          slotIndex: item.slotIndex,
          favTimeStr: item.favTimeStr,
          favTargetTime: item.favTargetTime,
          prevSlotTime: item.prevSlotTime,
          firstStopTime: item.firstStopTime,
          lastStopTime: item.lastStopTime,
          remain: item.remain,
          state: state,
          enRoute: item.enRoute,
        ));
      } else {
        departed.add(_SlotBoardItem(
          slotIndex: item.slotIndex,
          favTimeStr: item.favTimeStr,
          favTargetTime: item.favTargetTime,
          prevSlotTime: item.prevSlotTime,
          firstStopTime: item.firstStopTime,
          lastStopTime: item.lastStopTime,
          remain: item.remain,
          state: hasAnyUpcoming ? _SlotState.departed : _SlotState.endedToday,
          enRoute: item.enRoute,
        ));
      }
    }

    // 即将发车按距离现在的时间升序排列（最近的排最上）
    upcoming.sort((a, b) => a.remain.compareTo(b.remain));
    // 已发车沉底，按原班次顺序排列
    departed.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

    return [...upcoming, ...departed];
  }

  String _formatCountdown(Duration d) {
    final totalSecs = d.inSeconds;
    if (totalSecs < 0) return '已发车';
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return '还有 $hours 小时 ${two(mins)} 分 ${two(secs)} 秒';
    }
    return '还有 ${two(mins)} 分 ${two(secs)} 秒';
  }

  String _formatClock(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final prefs = AppPrefsController.instance;

    if (_loading || d == null) {
      return Scaffold(
        appBar: AppBar(title: Text(prefs.tr('校车动态看板', 'Live Bus Board'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final activeStops = _isInbound ? d.inboundStops : d.outboundStops;
    final boardItems = _buildSortedSlotItems(activeStops, _now);

    // 列表总数 = 顶部控制面板 (1) + 班次卡片数 (boardItems.length) + 底部说明 (1)
    final totalListCount = boardItems.length + 2;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.flight_takeoff_rounded, color: Color(0xFF2B5B84), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                prefs.tr('校车实时看板', 'Live Bus Board'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2B5B84).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatClock(_now),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Color(0xFF2B5B84),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: prefs.tr('站点与提醒设置', 'Stop & Reminder Settings'),
            icon: Icon(_showSettingsPanel ? Icons.tune_rounded : Icons.notifications_active_outlined),
            onPressed: () => setState(() => _showSettingsPanel = !_showSettingsPanel),
          ),
          PopupMenuButton<String>(
            tooltip: prefs.tr('路线管理与模板', 'Route Actions'),
            onSelected: (v) {
              if (v == 'switch') _openRouteSelectorSheet();
              if (v == 'export') _exportCurrentRoute();
              if (v == 'template') _downloadTemplate();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'switch',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.swap_horiz_rounded),
                  title: Text('切换 / 导入路线'),
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.ios_share_rounded),
                  title: Text('分享当前路线 JSON'),
                ),
              ),
              const PopupMenuItem(
                value: 'template',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_rounded),
                  title: Text('下载空 JSON 模板'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
        itemCount: totalListCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildBoardHeader(d, prefs, boardItems);
          }
          if (index == totalListCount - 1) {
            return _buildFooterCard();
          }
          final slotItem = boardItems[index - 1];
          final isFirstUpcoming = index == 1 &&
              (slotItem.state == _SlotState.imminent ||
                  slotItem.state == _SlotState.soon ||
                  slotItem.state == _SlotState.upcoming);
          return _buildFlightSlotCard(
            item: slotItem,
            stops: activeStops,
            isFirstUpcoming: isFirstUpcoming,
          );
        },
      ),
    );
  }

  /// 顶部控制区：当前路线条 + 常用站快选 + 去程/回程 SegmentedButton
  Widget _buildBoardHeader(BusRouteData d, AppPrefsController prefs, List<_SlotBoardItem> items) {
    final allEnded = items.isNotEmpty && items.every((e) => e.state == _SlotState.endedToday);
    final isWeekend = d.weekdaysOnly &&
        (_now.weekday == DateTime.saturday || _now.weekday == DateTime.sunday);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 路线切换栏 + 常用站快捷切换
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.38),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.alt_route_rounded, color: Color(0xFF2B5B84), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        prefs.isEn ? d.nameEn : d.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      onPressed: _openRouteSelectorSheet,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: Text(prefs.tr('切换/导入', 'Switch'), style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(height: 12),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFF7A22), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      prefs.tr('我的常用站：', 'My Stop: '),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isDense: true,
                          isExpanded: true,
                          value: _stops.contains(_favStop) ? _favStop : (_stops.isNotEmpty ? _stops.first : null),
                          items: _stops
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFFFF7A22),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _favStop = v);
                            _savePrefs();
                          },
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => _showSettingsPanel = !_showSettingsPanel),
                      child: Text(
                        _remEnabled ? '🔔 提前$_remMins分' : '🔕 提醒已关',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (_showSettingsPanel) ...[
                  const Divider(height: 14),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(prefs.tr('到站前手机震动提醒（仅周一至周五）', 'Arrival Vibration Reminder (Mon-Fri)')),
                    value: _remEnabled,
                    onChanged: (v) {
                      setState(() => _remEnabled = v);
                      _savePrefs();
                    },
                  ),
                  if (_remEnabled)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(prefs.tr('提前提醒时间', 'Remind Before'), style: const TextStyle(fontSize: 13)),
                        DropdownButton<int>(
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
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 2. 去程 / 回程 SegmentedButton（按时间自动推荐，可随时切换）
        SegmentedButton<bool>(
          segments: [
            ButtonSegment<bool>(
              value: false,
              icon: const Icon(Icons.directions_bus_rounded, size: 18),
              label: Text(prefs.tr('去程 → BUV', 'Outbound → BUV')),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: const Icon(Icons.home_rounded, size: 18),
              label: Text(prefs.tr('回程 ← 家', 'Inbound ← Home')),
            ),
          ],
          selected: {_isInbound},
          onSelectionChanged: (sel) {
            if (sel.isEmpty) return;
            setState(() => _isInbound = sel.first);
          },
        ),
        const SizedBox(height: 10),
        if (isWeekend)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.weekend_rounded, size: 18, color: Color(0xFFFF8F00)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '今天是周末（本路线仅周一至周五运行），以下为工作日班次预演',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else if (allEnded)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.nights_stay_rounded, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '今日该方向班次已全部结束 · 明日首班 ${items.first.favTimeStr}（$_favStop）',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 单个班次的机场航班屏动态卡片
  Widget _buildFlightSlotCard({
    required _SlotBoardItem item,
    required List<BusStopSchedule> stops,
    required bool isFirstUpcoming,
  }) {
    final isImminent = item.state == _SlotState.imminent;
    final isSoon = item.state == _SlotState.soon;
    final isUpcoming = item.state == _SlotState.upcoming;
    final isDeparted = item.state == _SlotState.departed || item.state == _SlotState.endedToday;

    // 五档状态色映射
    final Color statusColor;
    final String statusBadgeText;
    switch (item.state) {
      case _SlotState.imminent:
        statusColor = const Color(0xFFFF3D00); // 红橙告警色
        statusBadgeText = '即将到站 ≤5m';
      case _SlotState.soon:
        statusColor = const Color(0xFFFF8F00); // 琥珀色
        statusBadgeText = '快到了';
      case _SlotState.upcoming:
        statusColor = const Color(0xFF1976D2); // 航班蓝
        statusBadgeText = '待发车';
      case _SlotState.departed:
        statusColor = Colors.grey;
        statusBadgeText = '已发车';
      case _SlotState.endedToday:
        statusColor = Colors.blueGrey;
        statusBadgeText = '今日已结束';
    }

    // 区间进度计算（从上一班发车到本班到站）
    final totalSpanSecs = item.favTargetTime.difference(item.prevSlotTime).inSeconds;
    final elapsedSecs = _now.difference(item.prevSlotTime).inSeconds;
    final intervalProgress = totalSpanSecs <= 0
        ? 0.5
        : (elapsedSecs / totalSpanSecs).clamp(0.0, 1.0);

    String two(int n) => n.toString().padLeft(2, '0');
    final prevLabel = '${two(item.prevSlotTime.hour)}:${two(item.prevSlotTime.minute)}';

    final cardContent = AnimatedContainer(
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isImminent
              ? statusColor.withValues(alpha: _pulse ? 0.95 : 0.35)
              : (isFirstUpcoming
                  ? statusColor.withValues(alpha: 0.65)
                  : statusColor.withValues(alpha: 0.22)),
          width: isImminent ? (_pulse ? 2.4 : 1.4) : (isFirstUpcoming ? 1.8 : 1.0),
        ),
        boxShadow: isImminent
            ? [
                BoxShadow(
                  color: statusColor.withValues(alpha: _pulse ? 0.28 : 0.08),
                  blurRadius: _pulse ? 14 : 6,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部：🚌 Slot N · 时间 + 状态胶囊
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_bus_rounded, size: 17, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        'Slot ${item.slotIndex + 1} · ${item.favTimeStr}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: statusColor,
                          decoration: isDeparted ? TextDecoration.lineThrough : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isFirstUpcoming)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '下一班 NEXT',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 750),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isImminent && _pulse ? 0.28 : 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusBadgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 倒计时大字 + 行驶状态
            Row(
              children: [
                Expanded(
                  child: Text(
                    isDeparted
                        ? '已于 ${item.favTimeStr} 经过 $_favStop'
                        : _formatCountdown(item.remain),
                    style: TextStyle(
                      fontSize: isDeparted ? 13 : 18,
                      fontWeight: isImminent || isSoon || isFirstUpcoming ? FontWeight.w900 : FontWeight.bold,
                      color: isDeparted ? Colors.grey : statusColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (!isDeparted)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: item.enRoute ? const Color(0xFF26A69A) : statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.enRoute ? '行驶中' : (isUpcoming ? '待发车' : '即将进站'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: item.enRoute ? const Color(0xFF26A69A) : statusColor,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            // 2.3 水平区间进度条（从上一班到下一班，圆点标出当前时刻）
            if (!isDeparted) ...[
              const SizedBox(height: 10),
              _IntervalProgressBar(
                progress: intervalProgress,
                color: statusColor,
                leftLabel: item.slotIndex == 0 ? '候车起点 $prevLabel' : '上一班 $prevLabel',
                nowLabel: '现在 ${_formatClock(_now).substring(0, 5)}',
                rightLabel: '本站 ${item.favTimeStr}',
              ),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            // 站点时刻明细（高亮用户的常用站）
            ...stops.map((s) {
              final clean = _cleanStopName(s.name);
              final isFav = clean == _favStop || s.name.contains(_favStop);
              final tStr = item.slotIndex < s.times.length ? s.times[item.slotIndex] : '--:--';
              final stopDt = _parseTodayTime(tStr, _now);
              final stopPassed = _now.isAfter(stopDt);

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _favStop = clean);
                  _savePrefs();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isFav
                        ? const Color(0xFFFF7A22).withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isFav
                        ? Border.all(color: const Color(0xFFFF7A22).withValues(alpha: 0.45))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isFav
                            ? Icons.star_rounded
                            : (stopPassed ? Icons.check_circle_outline_rounded : Icons.radio_button_unchecked_rounded),
                        size: 15,
                        color: isFav
                            ? const Color(0xFFFF7A22)
                            : (stopPassed ? Colors.grey : statusColor),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isFav ? FontWeight.bold : FontWeight.normal,
                            color: isFav
                                ? const Color(0xFFFF7A22)
                                : (stopPassed && !isFav ? Colors.grey : null),
                            decoration: (isDeparted && !isFav) ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isFav)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF7A22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '← 你的常用站',
                            style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      Text(
                        tStr,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isFav ? FontWeight.w900 : FontWeight.w600,
                          color: isFav
                              ? const Color(0xFFFF7A22)
                              : (stopPassed ? Colors.grey : null),
                          decoration: isDeparted ? TextDecoration.lineThrough : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );

    if (isDeparted) {
      return Opacity(opacity: 0.56, child: cardContent);
    }
    return cardContent;
  }

  Widget _buildFooterCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.touch_app_rounded, color: Colors.teal),
        title: const Text('小贴士：点击卡片内任意站点即可设为常用站', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: const Text(
          '看板按距离当前时刻最近自动排序，≤5 分钟红橙呼吸提醒，已发车班次自动沉底置灰。右上角支持导入/分享自定义路线 JSON。',
          style: TextStyle(fontSize: 12),
        ),
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
}

/// 从「上一班发车」到「下一班到站」的水平进度条 + 当前时刻圆点指示器
class _IntervalProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final String leftLabel;
  final String nowLabel;
  final String rightLabel;

  const _IntervalProgressBar({
    required this.progress,
    required this.color,
    required this.leftLabel,
    required this.nowLabel,
    required this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const dotSize = 14.0;
            final dotLeft = ((width - dotSize) * p).clamp(0.0, width - dotSize);
            return SizedBox(
              height: 18,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    width: width,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    height: 6,
                    width: width * p,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Positioned(
                    left: dotLeft,
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leftLabel, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.outline)),
            Text(
              '● $nowLabel',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
            ),
            Text(rightLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ],
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
