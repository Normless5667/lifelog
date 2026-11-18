import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final bool enRoute;

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

/// 校车时刻表：机场航班屏动态看板 + 多路线管理
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
    toast(context, context.l10n.busFavStopToast(_favStop));
  }

  Future<void> _switchRoute(BusRouteData r) async {
    await BusService.setActiveRouteId(r.id);
    await _load();
    await ReminderService.syncAlarms();
    if (!mounted) return;
    toast(context, context.l10n.busSwitchedRouteToast(r.name));
  }

  Future<void> _downloadTemplate() async {
    final jsonStr = BusService.templateJsonString();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bus_route_template.json');
    await file.writeAsString(jsonStr);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'bus_route_template.json',
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
        subject: d.name,
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
      toast(context, context.l10n.busImportedRouteToast(imported.name));
    } on FormatException catch (e) {
      if (!mounted) return;
      _showValidationError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showValidationError('$e');
    }
  }

  void _showValidationError(String msg) {
    final l = context.l10n;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(l.busValidationFailedTitle)),
          ],
        ),
        content: Text(msg),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonGotIt)),
        ],
      ),
    );
  }

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

    final favStopObj = stops.firstWhere(
      (s) => L10nHelper.cleanBusStopName(s.name) == _favStop || s.name.contains(_favStop),
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

    upcoming.sort((a, b) => a.remain.compareTo(b.remain));
    departed.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

    return [...upcoming, ...departed];
  }

  String _formatCountdown(BuildContext context, Duration d) {
    final l = context.l10n;
    final totalSecs = d.inSeconds;
    if (totalSecs < 0) return l.busStatusDeparted;
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return l.busCountdownHoursMinsSecs(hours, two(mins), two(secs));
    }
    return l.busCountdownMinsSecs(two(mins), two(secs));
  }

  String _formatClock(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final l = context.l10n;

    if (_loading || d == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.busBoardTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final activeStops = _isInbound ? d.inboundStops : d.outboundStops;
    final boardItems = _buildSortedSlotItems(activeStops, _now);
    final totalListCount = boardItems.length + 2;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.flight_takeoff_rounded, color: Color(0xFF2B5B84), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.busBoardTitle,
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
            tooltip: l.busStopReminderSettings,
            icon: Icon(_showSettingsPanel ? Icons.tune_rounded : Icons.notifications_active_outlined),
            onPressed: () => setState(() => _showSettingsPanel = !_showSettingsPanel),
          ),
          PopupMenuButton<String>(
            tooltip: l.busRouteActions,
            onSelected: (v) {
              if (v == 'switch') _openRouteSelectorSheet();
              if (v == 'export') _exportCurrentRoute();
              if (v == 'template') _downloadTemplate();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'switch',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: Text(l.busMenuSwitchImport),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.ios_share_rounded),
                  title: Text(l.busMenuShareJson),
                ),
              ),
              PopupMenuItem(
                value: 'template',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_rounded),
                  title: Text(l.busMenuDownloadTemplate),
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
            return _buildBoardHeader(d, boardItems);
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
  Widget _buildBoardHeader(BusRouteData d, List<_SlotBoardItem> items) {
    final l = context.l10n;
    final allEnded = items.isNotEmpty && items.every((e) => e.state == _SlotState.endedToday);
    final isWeekend = d.weekdaysOnly &&
        (_now.weekday == DateTime.saturday || _now.weekday == DateTime.sunday);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                        context.isEnLocale ? d.nameEn : d.name,
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
                      label: Text(l.busSwitchImportBtn, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(height: 12),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFF7A22), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      l.busMyFavStopLabel,
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
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => _showSettingsPanel = !_showSettingsPanel),
                      icon: Icon(
                        _remEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                        size: 15,
                      ),
                      label: Text(
                        _remEnabled ? l.busReminderBadgeOn(_remMins) : l.busReminderBadgeOff,
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
                    title: Text(l.busVibrationSwitchTitle),
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
                        Text(l.busRemindBeforeLabel, style: const TextStyle(fontSize: 13)),
                        DropdownButton<int>(
                          value: _remMins,
                          items: [
                            for (final m in [5, 10, 15])
                              DropdownMenuItem(value: m, child: Text(l.busRemindMinsOption(m))),
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
        SegmentedButton<bool>(
          segments: [
            ButtonSegment<bool>(
              value: false,
              icon: const Icon(Icons.directions_bus_rounded, size: 18),
              label: Text(l.busOutboundSegment),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: const Icon(Icons.home_rounded, size: 18),
              label: Text(l.busInboundSegment),
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
            child: Row(
              children: [
                const Icon(Icons.weekend_rounded, size: 18, color: Color(0xFFFF8F00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.busWeekendBanner,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                    l.busEndedTodayBanner(items.first.favTimeStr, _favStop),
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
    final l = context.l10n;
    final isImminent = item.state == _SlotState.imminent;
    final isSoon = item.state == _SlotState.soon;
    final isUpcoming = item.state == _SlotState.upcoming;
    final isDeparted = item.state == _SlotState.departed || item.state == _SlotState.endedToday;

    final Color statusColor;
    final String statusBadgeText;
    switch (item.state) {
      case _SlotState.imminent:
        statusColor = const Color(0xFFFF3D00);
        statusBadgeText = l.busStatusImminent;
      case _SlotState.soon:
        statusColor = const Color(0xFFFF8F00);
        statusBadgeText = l.busStatusSoon;
      case _SlotState.upcoming:
        statusColor = const Color(0xFF1976D2);
        statusBadgeText = l.busStatusUpcoming;
      case _SlotState.departed:
        statusColor = Colors.grey;
        statusBadgeText = l.busStatusDeparted;
      case _SlotState.endedToday:
        statusColor = Colors.blueGrey;
        statusBadgeText = l.busStatusEnded;
    }

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
                    child: Text(
                      l.busNextBadge,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    isDeparted
                        ? l.busDepartedAtStop(_favStop, item.favTimeStr)
                        : _formatCountdown(context, item.remain),
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
                        item.enRoute
                            ? l.busEnRoute
                            : (isUpcoming ? l.busWaitingDepart : l.busArrivingSoon),
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
            if (!isDeparted) ...[
              const SizedBox(height: 10),
              _IntervalProgressBar(
                progress: intervalProgress,
                color: statusColor,
                leftLabel: item.slotIndex == 0
                    ? l.busProgressStart(prevLabel)
                    : l.busProgressPrev(prevLabel),
                nowLabel: l.busProgressNow(_formatClock(_now).substring(0, 5)),
                rightLabel: l.busProgressTarget(item.favTimeStr),
              ),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ...stops.map((s) {
              final clean = L10nHelper.cleanBusStopName(s.name);
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
                          L10nHelper.busStopDisplayName(context, s.name),
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
                          child: Text(
                            l.busYourFavStopTag,
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
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
    final l = context.l10n;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.touch_app_rounded, color: Colors.teal),
        title: Text(l.busFooterTipTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(
          l.busFooterTipSub,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  void _openRouteSelectorSheet() {
    final l = context.l10n;
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
                Expanded(
                  child: Text(l.busSheetTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _downloadTemplate();
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(l.busDownloadTemplateBtn),
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
                            child: Text(
                              context.isEnLocale ? r.nameEn : r.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (r.isBuiltin ? const Color(0xFF2B5B84) : const Color(0xFFFF7A22))
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              r.isBuiltin
                                  ? l.busBadgeBuiltin
                                  : (r.source == 'imported' ? l.busBadgeImported : l.busBadgeCustom),
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
                          l.busStopsCountSub(r.outboundStops.length, r.inboundStops.length),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: r.isBuiltin
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: l.commonEdit,
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _openCustomRouteDialog(existing: r);
                                  },
                                ),
                                IconButton(
                                  tooltip: l.commonDelete,
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    if (await confirm(context, l.busDeleteRouteConfirm(r.name))) {
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
                    label: Text(l.busManualCreateBtn),
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
                    label: Text(l.busImportJsonBtn),
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
        toast(context, context.l10n.busSwitchedRouteToast(saved.name));
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
    return L10nHelper.parseStopLines(raw)
        .map((e) => BusStopSchedule(name: e.$1, times: e.$2))
        .toList();
  }

  void _submit() {
    final l = context.l10n;
    final route = BusRouteData(
      id: widget.existing?.id ?? 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      nameEn: _name.text.trim(),
      school: _school.text.trim(),
      source: 'custom',
      outboundTitle: l.busOutboundSegment,
      outboundStops: _parseLines(_outboundText.text),
      inboundTitle: l.busInboundSegment,
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
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.existing == null ? l.busCustomDialogCreateTitle : l.busCustomDialogEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l.busCustomRouteNameLabel,
                hintText: 'BUV · Ecopark Route',
                prefixIcon: const Icon(Icons.alt_route_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _school,
              decoration: InputDecoration(
                labelText: l.busCustomSchoolLabel,
                prefixIcon: const Icon(Icons.school_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Text(l.busCustomOutboundHint, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _outboundText,
              maxLines: 4,
              decoration: const InputDecoration(),
            ),
            const SizedBox(height: 12),
            Text(l.busCustomInboundHint, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(l.busCustomValidateSaveBtn),
        ),
      ],
    );
  }
}
