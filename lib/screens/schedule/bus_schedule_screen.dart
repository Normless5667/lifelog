import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../db/repo.dart';
import '../../services/battery_probe_service.dart';
import '../../services/bus_service.dart';
import '../../services/reminder_service.dart';
import '../../widgets/common.dart';

/// 纯函数：计算当前时刻 [now] 在上一站发车时间 [t1] 与下一站到达时间 [t2] 之间的位置进度 (0.0 ~ 1.0)
double calcBusSegmentProgress(DateTime now, DateTime t1, DateTime t2) {
  final totalMs = t2.difference(t1).inMilliseconds;
  if (totalMs <= 0) {
    return now.isBefore(t1) ? 0.0 : 1.0;
  }
  final elapsedMs = now.difference(t1).inMilliseconds;
  return (elapsedMs / totalMs).clamp(0.0, 1.0);
}

enum _SlotState {
  imminent, // ≤ 5 分钟：红/橙 + 呼吸
  soon, // 6-15 分钟：琥珀色
  upcoming, // > 15 分钟：蓝色
  departed, // 已发车：灰色半透明
  endedToday, // 今日全部已结束：灰色沉底
}

class _SlotBoardItem {
  final int slotIndex; // 0-based
  final String originTimeStr;
  final String destTimeStr;
  final DateTime originTargetTime;
  final DateTime destTargetTime;
  final Duration remainToOrigin;
  final _SlotState state;
  final bool enRouteSegment;

  const _SlotBoardItem({
    required this.slotIndex,
    required this.originTimeStr,
    required this.destTimeStr,
    required this.originTargetTime,
    required this.destTargetTime,
    required this.remainToOrigin,
    required this.state,
    required this.enRouteSegment,
  });
}

/// 校车时刻表 v1.6：
/// - P0 省电架构：移除整页每秒 setState；通过 ValueNotifier<DateTime> 仅局部更新时钟与时间轴；
///   呼吸动画由独立 AnimationController 驱动；通过 RouteAware + WidgetsBindingObserver 在退后台或页面被遮挡时立刻停止计时器
/// - P1 起终点选择 + 垂直时间轴 + 平滑移动巴士图标（AnimatedPositioned 1s 线性连续插值）
class BusScheduleScreen extends StatefulWidget {
  const BusScheduleScreen({super.key});

  @override
  State<BusScheduleScreen> createState() => _BusScheduleScreenState();
}

class _BusScheduleScreenState extends State<BusScheduleScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  static const _timerTag = 'bus_board';
  List<BusRouteData> _allRoutes = [];
  BusRouteData? _data;
  List<String> _stops = [];
  String _originStop = '';
  String _destStop = '';
  bool _remEnabled = true;
  int _remMins = 10;
  bool _loading = true;

  late bool _isInbound;
  int? _selectedSlotIndex; // null 表示自动跟随下一班或正在行驶的班次
  bool _showSettingsPanel = false;

  Timer? _clockTimer;
  bool _routeVisible = true;
  bool _appInForeground = true;
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier<DateTime>(DateTime.now());
  late final AnimationController _pulseCtrl;
  late final AnimationController _refreshSpinCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isInbound = DateTime.now().hour >= 14;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _refreshSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      BatteryProbeService.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BatteryProbeService.routeObserver.unsubscribe(this);
    _stopLiveClock();
    _pulseCtrl.dispose();
    _refreshSpinCtrl.dispose();
    _nowNotifier.dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _stopLiveClock();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _nowNotifier.value = DateTime.now();
    _startLiveClockIfVisible();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _appInForeground = false;
      _stopLiveClock();
    } else if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _nowNotifier.value = DateTime.now();
      _startLiveClockIfVisible();
    }
  }

  void _startLiveClockIfVisible() {
    if (!_routeVisible || !_appInForeground) return;
    if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
    if (_clockTimer != null) return;
    BatteryProbeService.instance.onTimerStarted(_timerTag);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // 仅更新 ValueNotifier，绝不调用整页 setState！
      _nowNotifier.value = DateTime.now();
    });
  }

  void _stopLiveClock() {
    if (_clockTimer != null) {
      _clockTimer?.cancel();
      _clockTimer = null;
      BatteryProbeService.instance.onTimerStopped(_timerTag);
    }
    if (_pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
  }

  Future<void> _load({bool animateSpin = false}) async {
    if (animateSpin) {
      _refreshSpinCtrl.forward(from: 0);
    }
    final all = await BusService.loadAllRoutes(forceReload: true);
    final data = await BusService.load();
    final stops = await BusService.allStopNames();
    final fav = await BusService.favoriteStop();
    final en = await BusService.reminderEnabled();
    final mins = await BusService.reminderMinutesBefore();

    final savedOrig = await Repo.getKv('bus_orig_${data.id}');
    final savedDest = await Repo.getKv('bus_dest_${data.id}');

    final dirStops = (_isInbound ? data.inboundStops : data.outboundStops)
        .map((s) => L10nHelper.cleanBusStopName(s.name))
        .toList();

    String orig;
    String dest;
    if (savedOrig != null &&
        savedDest != null &&
        stops.contains(savedOrig) &&
        stops.contains(savedDest) &&
        savedOrig != savedDest) {
      orig = savedOrig;
      dest = savedDest;
    } else if (dirStops.length >= 2) {
      if (!_isInbound) {
        orig = dirStops.contains(fav) && fav != dirStops.last ? fav : dirStops.first;
        dest = dirStops.last;
      } else {
        orig = dirStops.first;
        dest = dirStops.contains(fav) && fav != dirStops.first ? fav : dirStops.last;
      }
    } else {
      orig = stops.isNotEmpty ? stops.first : '';
      dest = stops.length > 1 ? stops.last : orig;
    }

    if (!mounted) return;
    setState(() {
      _allRoutes = all;
      _data = data;
      _stops = stops;
      _originStop = orig;
      _destStop = dest;
      _remEnabled = en;
      _remMins = mins;
      _loading = false;
    });
    _nowNotifier.value = DateTime.now();
    _ensureDirectionMatchesStops(silent: true);
    _startLiveClockIfVisible();
  }

  /// 检查当前所选起点和终点的先后顺序；若在当前方向反了而在相反方向顺向，则自动切换去程/回程
  void _ensureDirectionMatchesStops({bool silent = false}) {
    final d = _data;
    if (d == null || _originStop.isEmpty || _destStop.isEmpty || _originStop == _destStop) return;

    final curList = (_isInbound ? d.inboundStops : d.outboundStops)
        .map((s) => L10nHelper.cleanBusStopName(s.name))
        .toList();
    final curOrigIdx = curList.indexOf(_originStop);
    final curDestIdx = curList.indexOf(_destStop);

    if (curOrigIdx >= 0 && curDestIdx >= 0 && curOrigIdx < curDestIdx) {
      return; // 当前方向顺序正确
    }

    final otherList = (!_isInbound ? d.inboundStops : d.outboundStops)
        .map((s) => L10nHelper.cleanBusStopName(s.name))
        .toList();
    final otherOrigIdx = otherList.indexOf(_originStop);
    final otherDestIdx = otherList.indexOf(_destStop);

    if (otherOrigIdx >= 0 && otherDestIdx >= 0 && otherOrigIdx < otherDestIdx) {
      setState(() {
        _isInbound = !_isInbound;
        _selectedSlotIndex = null;
      });
      if (!silent && mounted) {
        toast(context, context.l10n.busAutoSwitchedDirToast(_originStop, _destStop));
      }
    }
  }

  Future<void> _saveOriginDestAndPrefs() async {
    final d = _data;
    if (d != null) {
      await Repo.setKv('bus_orig_${d.id}', _originStop);
      await Repo.setKv('bus_dest_${d.id}', _destStop);
    }
    if (_originStop.isNotEmpty) {
      await BusService.setFavoriteStop(_originStop);
    }
    await BusService.setReminderEnabled(_remEnabled);
    await BusService.setReminderMinutesBefore(_remMins);
    await ReminderService.syncAlarms();
  }

  void _swapOriginDest() {
    if (_originStop.isEmpty || _destStop.isEmpty) return;
    setState(() {
      final tmp = _originStop;
      _originStop = _destStop;
      _destStop = tmp;
      _selectedSlotIndex = null;
    });
    _ensureDirectionMatchesStops();
    _saveOriginDestAndPrefs();
  }

  Future<void> _switchRoute(BusRouteData r) async {
    await BusService.setActiveRouteId(r.id);
    _selectedSlotIndex = null;
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

  /// 解析 HH:mm 为当日 DateTime；若 [notBefore] 存在且解析结果早于 [notBefore]（跨午夜），自动 +1 天避免算出负数
  static DateTime parseStopDateTime(String hhmm, DateTime refDay, {DateTime? notBefore}) {
    final parts = hhmm.split(':');
    var dt = refDay;
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      dt = DateTime(refDay.year, refDay.month, refDay.day, h, m);
    }
    if (notBefore != null && dt.isBefore(notBefore)) {
      dt = dt.add(const Duration(days: 1));
    }
    return dt;
  }

  /// 获取经过起终点过滤后的站点子列表（若起点=终点则返回空列表并提示错误）
  List<BusStopSchedule> _filteredSegmentStops(List<BusStopSchedule> dirStops) {
    if (dirStops.isEmpty || _originStop == _destStop) return const [];
    final origIdx = dirStops.indexWhere((s) => L10nHelper.cleanBusStopName(s.name) == _originStop);
    final destIdx = dirStops.indexWhere((s) => L10nHelper.cleanBusStopName(s.name) == _destStop);
    if (origIdx >= 0 && destIdx >= 0) {
      if (origIdx < destIdx) {
        return dirStops.sublist(origIdx, destIdx + 1);
      } else {
        return dirStops.sublist(destIdx, origIdx + 1).reversed.toList();
      }
    }
    return dirStops;
  }

  List<_SlotBoardItem> _buildSortedSlotItems(List<BusStopSchedule> segmentStops, DateTime now) {
    if (segmentStops.isEmpty || segmentStops.first.times.isEmpty) return const [];
    final origStop = segmentStops.first;
    final destStop = segmentStops.last;
    final slotCount = origStop.times.length;

    final rawItems = <({
      int slotIndex,
      String originTimeStr,
      String destTimeStr,
      DateTime originTargetTime,
      DateTime destTargetTime,
      Duration remainToOrigin,
      bool enRouteSegment,
    })>[];

    for (var i = 0; i < slotCount; i++) {
      final origStr = i < origStop.times.length ? origStop.times[i] : origStop.times.last;
      final destStr = i < destStop.times.length ? destStop.times[i] : origStr;

      final origDt = parseStopDateTime(origStr, now);
      final destDt = parseStopDateTime(destStr, now, notBefore: origDt);
      final remain = origDt.difference(now);
      final enRoute = !now.isBefore(origDt) && now.isBefore(destDt);

      rawItems.add((
        slotIndex: i,
        originTimeStr: origStr,
        destTimeStr: destStr,
        originTargetTime: origDt,
        destTargetTime: destDt,
        remainToOrigin: remain,
        enRouteSegment: enRoute,
      ));
    }

    final hasAnyActive = rawItems.any((e) => !e.remainToOrigin.isNegative || e.enRouteSegment);
    final upcoming = <_SlotBoardItem>[];
    final departed = <_SlotBoardItem>[];

    for (final item in rawItems) {
      if (!item.remainToOrigin.isNegative || item.enRouteSegment) {
        final secs = item.remainToOrigin.inSeconds;
        final state = secs <= 300
            ? _SlotState.imminent
            : (secs <= 900 ? _SlotState.soon : _SlotState.upcoming);
        upcoming.add(_SlotBoardItem(
          slotIndex: item.slotIndex,
          originTimeStr: item.originTimeStr,
          destTimeStr: item.destTimeStr,
          originTargetTime: item.originTargetTime,
          destTargetTime: item.destTargetTime,
          remainToOrigin: item.remainToOrigin,
          state: state,
          enRouteSegment: item.enRouteSegment,
        ));
      } else {
        departed.add(_SlotBoardItem(
          slotIndex: item.slotIndex,
          originTimeStr: item.originTimeStr,
          destTimeStr: item.destTimeStr,
          originTargetTime: item.originTargetTime,
          destTargetTime: item.destTargetTime,
          remainToOrigin: item.remainToOrigin,
          state: hasAnyActive ? _SlotState.departed : _SlotState.endedToday,
          enRouteSegment: false,
        ));
      }
    }

    upcoming.sort((a, b) => a.originTargetTime.compareTo(b.originTargetTime));
    departed.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    return [...upcoming, ...departed];
  }

  static String _formatClock(DateTime dt) {
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

    final dirStops = _isInbound ? d.inboundStops : d.outboundStops;
    final sameStopError = _originStop.isNotEmpty && _originStop == _destStop;
    final segmentStops = sameStopError ? const <BusStopSchedule>[] : _filteredSegmentStops(dirStops);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.directions_bus_rounded, color: Color(0xFF2B5B84), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.busBoardTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 独立局部刷新的时钟胶囊（不引发整页 setState）
            ValueListenableBuilder<DateTime>(
              valueListenable: _nowNotifier,
              builder: (_, now, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B5B84).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatClock(now),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Color(0xFF2B5B84),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            icon: RotationTransition(
              turns: _refreshSpinCtrl,
              child: const Icon(Icons.refresh_rounded),
            ),
            onPressed: () async {
              await _load(animateSpin: true);
              if (context.mounted) toast(context, l.busRefreshSpinToast);
            },
          ),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
        children: [
          _buildRouteAndOriginDestHeader(d),
          if (sameStopError)
            Card(
              color: Colors.redAccent.withValues(alpha: 0.14),
              child: ListTile(
                leading: const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                title: Text(
                  l.busSameStopError,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.redAccent),
                ),
              ),
            )
          else if (segmentStops.isNotEmpty)
            // 核心动态区域：由 ValueListenableBuilder<DateTime> 驱动，仅重绘时间轴与班次状态
            ValueListenableBuilder<DateTime>(
              valueListenable: _nowNotifier,
              builder: (context, now, _) {
                final boardItems = _buildSortedSlotItems(segmentStops, now);
                if (boardItems.isEmpty) return const SizedBox.shrink();

                final allEnded = boardItems.every((e) => e.state == _SlotState.endedToday);
                final isWeekend = d.weekdaysOnly &&
                    (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday);

                final activeItem = _selectedSlotIndex != null
                    ? boardItems.firstWhere(
                        (e) => e.slotIndex == _selectedSlotIndex,
                        orElse: () => boardItems.first,
                      )
                    : boardItems.first;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.nights_stay_rounded, size: 22, color: Colors.blueGrey),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.busNoMoreTripsToday,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l.busNoMoreTripsSub(segmentStops.first.times.first),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    _buildSlotSelectorBar(boardItems, activeItem, allEnded),
                    const SizedBox(height: 8),
                    _LiveRouteTimelineCard(
                      item: activeItem,
                      segmentStops: segmentStops,
                      now: now,
                      allEndedToday: allEnded,
                      pulseAnimation: _pulseCtrl,
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 8),
          _buildFooterCard(),
        ],
      ),
    );
  }

  /// 顶部：当前路线 + 起点/终点双下拉 + 一键交换按钮 + 去程/回程切换
  Widget _buildRouteAndOriginDestHeader(BusRouteData d) {
    final l = context.l10n;
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
                const Divider(height: 14),
                // 2.1 起点 + 终点双下拉 + 一键交换按钮
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            key: ValueKey('orig-${d.id}-$_originStop'),
                            initialValue: _stops.contains(_originStop) ? _originStop : (_stops.isNotEmpty ? _stops.first : null),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l.busOriginLabel,
                              prefixIcon: const Icon(Icons.trip_origin_rounded, size: 18, color: Color(0xFF26A69A)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: _stops
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _originStop = v;
                                _selectedSlotIndex = null;
                              });
                              _ensureDirectionMatchesStops();
                              _saveOriginDestAndPrefs();
                            },
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey('dest-${d.id}-$_destStop'),
                            initialValue: _stops.contains(_destStop) ? _destStop : (_stops.isNotEmpty ? _stops.last : null),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l.busDestinationLabel,
                              prefixIcon: const Icon(Icons.place_rounded, size: 18, color: Color(0xFFFF7A22)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: _stops
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _destStop = v;
                                _selectedSlotIndex = null;
                              });
                              _ensureDirectionMatchesStops();
                              _saveOriginDestAndPrefs();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: l.busSwapStopsTooltip,
                      onPressed: _swapOriginDest,
                      icon: const Icon(Icons.swap_vert_rounded, size: 24),
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
                      _saveOriginDestAndPrefs();
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
                            _saveOriginDestAndPrefs();
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
            final nextIn = sel.first;
            final nextStops = (nextIn ? d.inboundStops : d.outboundStops)
                .map((s) => L10nHelper.cleanBusStopName(s.name))
                .toList();
            setState(() {
              _isInbound = nextIn;
              _selectedSlotIndex = null;
              if (nextStops.length >= 2) {
                final oIdx = nextStops.indexOf(_originStop);
                final dIdx = nextStops.indexOf(_destStop);
                if (oIdx < 0 || dIdx < 0 || oIdx > dIdx) {
                  _originStop = nextStops.first;
                  _destStop = nextStops.last;
                }
              }
            });
            _saveOriginDestAndPrefs();
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  /// 班次快选横条（按即将发车升序排列，最近一班排最前，已发车沉后置灰）
  Widget _buildSlotSelectorBar(List<_SlotBoardItem> items, _SlotBoardItem activeItem, bool allEnded) {
    final l = context.l10n;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(l.busSelectSlotLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final it = entry.value;
            final selected = it.slotIndex == activeItem.slotIndex;
            final isDeparted = it.state == _SlotState.departed || it.state == _SlotState.endedToday;
            final isNext = idx == 0 && !isDeparted;

            final Color chipColor;
            switch (it.state) {
              case _SlotState.imminent:
                chipColor = const Color(0xFFFF3D00);
              case _SlotState.soon:
                chipColor = const Color(0xFFFF8F00);
              case _SlotState.upcoming:
                chipColor = const Color(0xFF1976D2);
              case _SlotState.departed:
              case _SlotState.endedToday:
                chipColor = Colors.grey;
            }

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                visualDensity: VisualDensity.compact,
                selected: selected,
                selectedColor: chipColor.withValues(alpha: 0.22),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Slot ${it.slotIndex + 1} (${it.originTimeStr})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected || isNext ? FontWeight.bold : FontWeight.normal,
                        color: isDeparted ? Colors.grey : chipColor,
                        decoration: isDeparted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (isNext) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: chipColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l.busNextBadge,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                onSelected: (_) => setState(() => _selectedSlotIndex = it.slotIndex),
              ),
            );
          }),
        ],
      ),
    );
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

/// 2.2 垂直时间轴线路图 + 平滑移动车辆位置动画卡片
class _LiveRouteTimelineCard extends StatelessWidget {
  static const double _rowHeight = 62.0;

  final _SlotBoardItem item;
  final List<BusStopSchedule> segmentStops;
  final DateTime now;
  final bool allEndedToday;
  final Animation<double> pulseAnimation;

  const _LiveRouteTimelineCard({
    required this.item,
    required this.segmentStops,
    required this.now,
    required this.allEndedToday,
    required this.pulseAnimation,
  });

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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isImminent = item.state == _SlotState.imminent;
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

    // 解析该区间内每一站的时刻（处理跨午夜）
    final stopTimes = <DateTime>[];
    DateTime? prevDt;
    for (final s in segmentStops) {
      final tStr = item.slotIndex < s.times.length ? s.times[item.slotIndex] : s.times.last;
      final dt = _BusScheduleScreenState.parseStopDateTime(tStr, now, notBefore: prevDt);
      stopTimes.add(dt);
      prevDt = dt;
    }

    // 计算巴士当前所在的区间 (activeSegIdx) 和区间内插值进度 (segProgress: 0.0~1.0)
    int? activeSegIdx;
    double segProgress = 0.0;
    int? currentStopIdx;

    if (!allEndedToday && stopTimes.length >= 2) {
      if (!now.isBefore(stopTimes.first) && now.isBefore(stopTimes.last)) {
        for (var k = 0; k < stopTimes.length - 1; k++) {
          final t1 = stopTimes[k];
          final t2 = stopTimes[k + 1];
          if (!now.isBefore(t1) && now.isBefore(t2)) {
            activeSegIdx = k;
            segProgress = calcBusSegmentProgress(now, t1, t2);
            if (segProgress < 0.18) {
              currentStopIdx = k;
            } else if (segProgress > 0.88) {
              currentStopIdx = k + 1;
            }
            break;
          }
        }
      } else if (now.difference(stopTimes.first).inSeconds.abs() <= 45) {
        currentStopIdx = 0;
        activeSegIdx = 0;
        segProgress = 0.0;
      }
    }

    final busCenterY = activeSegIdx != null
        ? (activeSegIdx + segProgress) * _rowHeight + (_rowHeight / 2)
        : null;

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        final pulseVal = pulseAnimation.value;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isImminent
                  ? statusColor.withValues(alpha: 0.35 + 0.6 * pulseVal)
                  : statusColor.withValues(alpha: 0.35),
              width: isImminent ? (1.4 + 1.0 * pulseVal) : 1.4,
            ),
            boxShadow: isImminent
                ? [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.08 + 0.2 * pulseVal),
                      blurRadius: 6 + 8 * pulseVal,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 卡片头部：Slot + 倒计时/状态胶囊
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
                        l.busTimelineTitle('Slot ${item.slotIndex + 1} · ${item.originTimeStr} → ${item.destTimeStr}'),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          color: statusColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    allEndedToday
                        ? l.busNoMoreTripsToday
                        : (isDeparted
                            ? l.busDepartedAtStop(
                                L10nHelper.cleanBusStopName(segmentStops.first.name),
                                item.originTimeStr,
                              )
                            : (item.enRouteSegment
                                ? l.busBusHereLabel((segProgress * 100).round())
                                : _formatCountdown(context, item.remainToOrigin))),
                    style: TextStyle(
                      fontSize: isDeparted || allEndedToday ? 13.5 : 17,
                      fontWeight: FontWeight.w900,
                      color: isDeparted || allEndedToday ? Colors.grey : statusColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (!isDeparted && !allEndedToday)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: item.enRouteSegment ? const Color(0xFF26A69A) : statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.enRouteSegment ? l.busEnRoute : l.busWaitingDepart,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: item.enRouteSegment ? const Color(0xFF26A69A) : statusColor,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // 垂直时间轴 + 连续插值平滑移动的巴士图标
            SizedBox(
              height: segmentStops.length * _rowHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. 底层：各站点圆点、连接线（已过实心绿、未走虚线灰）与站点信息
                  Column(
                    children: [
                      for (var k = 0; k < segmentStops.length; k++)
                        _buildTimelineStopRow(
                          context: context,
                          index: k,
                          totalStops: segmentStops.length,
                          stop: segmentStops[k],
                          stopTime: stopTimes[k],
                          isCurrent: currentStopIdx == k,
                          isPassed: !allEndedToday &&
                              currentStopIdx != k &&
                              now.isAfter(stopTimes[k]),
                          activeSegIdx: activeSegIdx,
                          segProgress: segProgress,
                          statusColor: statusColor,
                        ),
                    ],
                  ),
                  // 2. 顶层：平滑移动的巴士图标（AnimatedPositioned 1 秒线性补间，连续滑动不跳格）
                  if (busCenterY != null)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 980),
                      curve: Curves.linear,
                      top: (busCenterY - 16).clamp(0.0, segmentStops.length * _rowHeight - 32),
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF26A69A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF26A69A).withValues(alpha: 0.45),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_bus_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineStopRow({
    required BuildContext context,
    required int index,
    required int totalStops,
    required BusStopSchedule stop,
    required DateTime stopTime,
    required bool isCurrent,
    required bool isPassed,
    required int? activeSegIdx,
    required double segProgress,
    required Color statusColor,
  }) {
    final l = context.l10n;
    final isFirst = index == 0;
    final isLast = index == totalStops - 1;
    final tStr = item.slotIndex < stop.times.length ? stop.times[item.slotIndex] : stop.times.last;

    // 计算距该站的剩余分钟数（跨午夜及已过站安全处理，绝不显示负数）
    final diffSecs = stopTime.difference(now).inSeconds;
    final minsUntil = (diffSecs / 60).ceil();

    // 上半段连接线是否已走过
    final topLinePassed = index > 0 &&
        !allEndedToday &&
        (isPassed || isCurrent || (activeSegIdx != null && activeSegIdx >= index - 1));
    // 下半段连接线是否已走过
    final bottomLinePassed = !isLast &&
        !allEndedToday &&
        (isPassed || (activeSegIdx != null && activeSegIdx >= index));

    String rightStatusText = '';
    Color rightStatusColor = Colors.grey;
    if (allEndedToday) {
      rightStatusText = l.busNoMoreTripsToday;
      rightStatusColor = Colors.blueGrey;
    } else if (isCurrent) {
      rightStatusText = l.busStopCurrentTag;
      rightStatusColor = const Color(0xFF26A69A);
    } else if (isPassed || diffSecs < 0) {
      rightStatusText = l.busStopPassedTag;
      rightStatusColor = Colors.grey;
    } else if (diffSecs <= 60) {
      rightStatusText = l.busStopArrivingNowTag;
      rightStatusColor = const Color(0xFFFF3D00);
    } else {
      rightStatusText = l.busStopInMinutesTag(minsUntil);
      rightStatusColor = minsUntil <= 5
          ? const Color(0xFFFF3D00)
          : (minsUntil <= 15 ? const Color(0xFFFF8F00) : const Color(0xFF1976D2));
    }

    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          // 左侧时间轴列（宽 44dp）
          SizedBox(
            width: 44,
            child: Column(
              children: [
                // 上半段连接线
                Expanded(
                  child: isFirst
                      ? const SizedBox.shrink()
                      : CustomPaint(
                          size: const Size(3, double.infinity),
                          painter: _TimelineSegmentPainter(
                            isSolidGreen: topLinePassed,
                          ),
                        ),
                ),
                // 站点圆点：已过站=实心灰，当前站=实心绿+光晕，未到站=空心圆
                Container(
                  width: isCurrent ? 22 : 14,
                  height: isCurrent ? 22 : 14,
                  alignment: Alignment.center,
                  decoration: isCurrent
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF26A69A).withValues(alpha: 0.22),
                        )
                      : null,
                  child: Container(
                    width: isCurrent ? 12 : 11,
                    height: isCurrent ? 12 : 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCurrent
                          ? const Color(0xFF26A69A)
                          : (isPassed || allEndedToday
                              ? Colors.grey
                              : Theme.of(context).colorScheme.surface),
                      border: (!isCurrent && !isPassed && !allEndedToday)
                          ? Border.all(color: statusColor, width: 2.4)
                          : null,
                    ),
                  ),
                ),
                // 下半段连接线
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : CustomPaint(
                          size: const Size(3, double.infinity),
                          painter: _TimelineSegmentPainter(
                            isSolidGreen: bottomLinePassed,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // 右侧站点名 + 起终点标签 + 时间 + 倒计时/状态
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCurrent
                    ? const Color(0xFF26A69A).withValues(alpha: 0.12)
                    : (isFirst || isLast
                        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.22)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (isFirst || isLast)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isFirst ? const Color(0xFF26A69A) : const Color(0xFFFF7A22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isFirst ? l.busStopOriginTag : l.busStopDestTag,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      L10nHelper.busStopDisplayName(context, stop.name),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent || isFirst || isLast ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent
                            ? const Color(0xFF26A69A)
                            : (isPassed ? Colors.grey : null),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tStr,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isPassed ? Colors.grey : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: Text(
                      rightStatusText,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isCurrent || (!isPassed && minsUntil <= 15)
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: rightStatusColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 绘制垂直时间轴连接线：已走过为实心绿线，未走过为虚线灰线
class _TimelineSegmentPainter extends CustomPainter {
  final bool isSolidGreen;

  const _TimelineSegmentPainter({required this.isSolidGreen});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    if (isSolidGreen) {
      final paint = Paint()
        ..color = const Color(0xFF26A69A)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), paint);
    } else {
      final paint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.55)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      const dashHeight = 4.0;
      const dashSpace = 3.5;
      double startY = 0;
      while (startY < size.height) {
        final endY = (startY + dashHeight).clamp(0.0, size.height);
        canvas.drawLine(Offset(centerX, startY), Offset(centerX, endY), paint);
        startY += dashHeight + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineSegmentPainter oldDelegate) =>
      oldDelegate.isSolidGreen != isSolidGreen;
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
