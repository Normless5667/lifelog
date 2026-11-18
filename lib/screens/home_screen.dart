import 'package:flutter/material.dart';

import '../db/repo.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/bus_service.dart';
import '../services/reminder_service.dart';
import '../services/step_service.dart';
import '../services/targets.dart';
import '../services/usage_telemetry_service.dart';
import '../services/weather_service.dart';
import '../services/widget_service.dart';
import '../utils/date_utils.dart';
import '../widgets/common.dart';
import 'body/body_screen.dart';
import 'body/onboarding_sheet.dart';
import 'diet/food_confirm_sheet.dart';
import 'schedule/bus_schedule_screen.dart';
import 'settings/battery_diagnostics_screen.dart';
import 'settings/settings_screen.dart';

/// 今日仪表盘（生活助手）：
/// - Open-Meteo 实时天气卡片（GPS 优先 + 6 小时定位缓存 + 手动城市切换）
/// - 校车下一班倒计时卡片（点按进入机场航班屏动态看板）
/// - 硬件级自动计步器进度环（TYPE_STEP_COUNTER）
/// - 连续打卡天数 (Streak) + 一句话 AI 速记饮食 + 右下角快捷记录 FAB
/// - 自动同步更新安卓桌面小组件 (AppWidget)
class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigate;
  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _quickFoodCtrl = TextEditingController();
  late final AnimationController _weatherSpinCtrl;
  bool _loading = true;
  bool _busyQuickAi = false;
  bool _hasProfile = true;
  int _streak = 0;
  DayTotals _totals = DayTotals.of(const []);
  DailyTargets _targets = const DailyTargets(2000, 100, 250, 55);
  List<Course> _todayCourses = [];
  int _week = 0;
  List<Workout> _todayWorkouts = [];
  List<CardioRecord> _todayCardios = [];
  int _todaySets = 0;
  BodyRecord? _latestWeight;
  Profile _profile = Profile();

  WeatherInfo? _weather;
  String _busRouteName = 'BUV · Hai Ba Trung Route';
  String _busStop = 'TIMES CITY';
  String _busDirection = '';
  String _busNextTime = '--:--';
  int _busMinsUntil = -1;
  bool _busIsWeekend = false;
  bool _stepSupported = true;
  bool _stepGranted = true;
  int _todaySteps = 0;
  int _stepGoal = 8000;
  double _stepBurnKcal = 0;

  @override
  void initState() {
    super.initState();
    _weatherSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    WidgetService.init();
    _load(checkOnboarding: true);
  }

  @override
  void dispose() {
    _weatherSpinCtrl.dispose();
    _quickFoodCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool checkOnboarding = false}) async {
    final t = today();
    final meals = await Repo.getMeals(t);
    final weight = await Repo.latestBodyRecordWithWeight();
    final wKg = weight?.weight ?? 65;

    final stepState = await StepService.getTodaySteps(weightKg: wKg);
    final targets = await DailyTargets.load(date: t);
    final hasProfile = await Repo.hasProfile();
    final onboardingDone = await Repo.isOnboardingDone();
    final profile = await Repo.getProfile();
    final streak = await Repo.calculateStreak();
    final courses = await Repo.getCourses();
    final start = await Repo.getSemesterStart();
    final week = weekOfSemester(start, DateTime.now());
    final wd = DateTime.now().weekday;
    final todayCourses = courses.where((c) => c.weekday == wd && c.activeInWeek(week)).toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
    final workouts = (await Repo.getWorkouts(from: t)).where((w) => w.date == t).toList();
    final cardios = await Repo.getCardioRecords(date: t);
    var sets = 0;
    for (final w in workouts) {
      sets += (await Repo.getSets(w.id!)).where((s) => !s.isWarmup).length;
    }

    final bus = await BusService.nextBusSummary();
    final weather = await WeatherService.getWeather();

    final totals = DayTotals.of(meals);
    WidgetService.sync(force: true);
    ReminderService.syncAlarms();

    if (!mounted) return;
    setState(() {
      _totals = totals;
      _targets = targets;
      _hasProfile = hasProfile;
      _profile = profile;
      _streak = streak;
      _todayCourses = todayCourses;
      _week = week;
      _todayWorkouts = workouts;
      _todayCardios = cardios;
      _todaySets = sets;
      _latestWeight = weight;
      _busRouteName = bus.routeName;
      _busStop = bus.stopName;
      _busDirection = bus.direction;
      _busNextTime = bus.nextTime;
      _busMinsUntil = bus.minutesUntil;
      _busIsWeekend = bus.isWeekend;
      _stepSupported = stepState.supported;
      _stepGranted = stepState.granted;
      _todaySteps = stepState.todaySteps;
      _stepGoal = stepState.goal;
      _stepBurnKcal = stepState.burnedKcal;
      _weather = weather;
      _loading = false;
    });

    if (checkOnboarding && !onboardingDone && !hasProfile && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => OnboardingSheet(initialProfile: profile, initialWeight: weight?.weight),
          ),
        );
        if (saved == true) _load();
      });
    }
  }

  Future<void> _open(Widget page) async {
    final prevPage = UsageTelemetryService.instance.currentPage;
    if (page is BusScheduleScreen) {
      UsageTelemetryService.instance.trackFeature('bus_board', 'tap');
      UsageTelemetryService.instance.enterPage('bus_board', source: 'push');
    } else if (page is BodyScreen) {
      UsageTelemetryService.instance.trackFeature('log_weight', 'tap');
      UsageTelemetryService.instance.enterPage('body', source: 'push');
    } else if (page is SettingsScreen) {
      UsageTelemetryService.instance.enterPage('settings', source: 'push');
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    UsageTelemetryService.instance.enterPage(prevPage, source: 'tab');
    _load();
  }

  int _guessMealType() {
    final h = DateTime.now().hour;
    if (h < 10) return 0;
    if (h < 15) return 1;
    if (h < 21) return 2;
    return 3;
  }

  Future<void> _submitQuickFood() async {
    final desc = _quickFoodCtrl.text.trim();
    if (desc.isEmpty || _busyQuickAi) return;
    FocusScope.of(context).unfocus();
    final t0 = DateTime.now().millisecondsSinceEpoch;
    UsageTelemetryService.instance.trackFeature('ai_log', 'tap');
    setState(() => _busyQuickAi = true);
    try {
      final res = await AiService.estimateFoodText(desc);
      if (!mounted) return;
      setState(() => _busyQuickAi = false);
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FoodConfirmSheet(
          date: today(),
          initialMealType: _guessMealType(),
          estimates: res.foods,
          aiNote: res.note,
        ),
      );
      final dur = DateTime.now().millisecondsSinceEpoch - t0;
      if (saved == true) {
        UsageTelemetryService.instance.trackFeature('ai_log', 'success', durationMs: dur);
        _quickFoodCtrl.clear();
        _load();
      } else {
        UsageTelemetryService.instance.trackFeature('ai_log', 'cancel', durationMs: dur);
      }
    } catch (e) {
      final dur = DateTime.now().millisecondsSinceEpoch - t0;
      UsageTelemetryService.instance.trackFeature('ai_log', 'fail', durationMs: dur, errorMsg: '$e');
      if (!mounted) return;
      setState(() => _busyQuickAi = false);
      showAiError(context, e, onOpenSettings: () => _open(const SettingsScreen()));
    }
  }

  void _openQuickRecordMenu() {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bolt_rounded, color: Color(0xFFFF7A22)),
              title: Text(l.homeQuickRecord, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x22FF7A22),
                child: Icon(Icons.restaurant_rounded, color: Color(0xFFFF7A22)),
              ),
              title: Text(l.homeQuickDiet),
              onTap: () {
                Navigator.pop(ctx);
                widget.onNavigate(2);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x22EF5350),
                child: Icon(Icons.fitness_center_rounded, color: Color(0xFFEF5350)),
              ),
              title: Text(l.homeQuickWorkout),
              onTap: () {
                Navigator.pop(ctx);
                widget.onNavigate(3);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x2242A5F5),
                child: Icon(Icons.monitor_weight_rounded, color: Color(0xFF42A5F5)),
              ),
              title: Text(l.homeQuickWeight),
              onTap: () {
                Navigator.pop(ctx);
                _open(const BodyScreen());
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x222B5B84),
                child: Icon(Icons.directions_bus_rounded, color: Color(0xFF2B5B84)),
              ),
              title: Text(l.homeQuickBus),
              onTap: () {
                Navigator.pop(ctx);
                _open(const BusScheduleScreen());
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x2226A69A),
                child: Icon(Icons.widgets_rounded, color: Color(0xFF26A69A)),
              ),
              title: Text(l.widgetGuideTitle),
              onTap: () {
                Navigator.pop(ctx);
                showAddHomeWidgetGuideDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.wb_sunny_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${now.month}/${now.day} ${L10nHelper.weekdayLabel(context, now.weekday)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.busBoardTitle,
            icon: const Icon(Icons.directions_bus_rounded),
            onPressed: () => _open(const BusScheduleScreen()),
          ),
          IconButton(
            tooltip: l.bodyTitle,
            icon: const Icon(Icons.monitor_weight_rounded),
            onPressed: () => _open(const BodyScreen()),
          ),
          IconButton(
            tooltip: l.settingsTitle,
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openQuickRecordMenu,
        tooltip: l.homeQuickRecord,
        backgroundColor: const Color(0xFFFF7A22),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  _streakAndWeatherSection(),
                  _busCard(),
                  const SizedBox(height: 8),
                  _quickHeroBanner(),
                  const SizedBox(height: 8),
                  _quickMealInputCard(),
                  if (!_hasProfile) _profilePrompt(),
                  CalorieSummaryCard(totals: _totals, targets: _targets, onTap: () => widget.onNavigate(2)),
                  _stepCounterCard(),
                  SectionTitle(
                    _week > 0 ? l.homeTodayClassesWeek(_week) : l.homeTodayClasses,
                    icon: Icons.school_rounded,
                    iconColor: const Color(0xFF2B5B84),
                    trailing: TextButton.icon(
                      onPressed: () => widget.onNavigate(1),
                      icon: const Icon(Icons.calendar_view_week_rounded, size: 16),
                      label: Text(l.homeAllSchedule),
                    ),
                  ),
                  _coursesCard(),
                  SectionTitle(
                    l.homeTodayWorkoutTitle,
                    icon: Icons.fitness_center_rounded,
                    iconColor: const Color(0xFFEF5350),
                    trailing: TextButton.icon(
                      onPressed: () => widget.onNavigate(3),
                      icon: const Icon(Icons.chevron_right, size: 18),
                      label: Text(l.homeGoWorkout),
                    ),
                  ),
                  _workoutCard(),
                  SectionTitle(
                    l.homeBodyStatus,
                    icon: Icons.favorite_rounded,
                    iconColor: const Color(0xFFEC407A),
                  ),
                  _bodyCard(),
                  const SizedBox(height: 12),
                  _aiBannerCard(),
                ],
              ),
            ),
    );
  }

  /// 标题下方：打卡连续天数激励胶囊 + 两行精简天气卡片
  Widget _streakAndWeatherSection() {
    final w = _weather;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF7A22).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF7A22).withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, size: 16, color: Color(0xFFFF7A22)),
                    const SizedBox(width: 4),
                    Text(
                      l.homeStreakDays(_streak),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF7A22),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _streak > 0 ? l.homeStreakKeepGoing : l.homeStreakStartHint,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (w != null)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _openWeatherCityQuickSheet,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Text(w.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${fmtNum(w.temperature)}°C ${L10nHelper.weatherConditionLabel(context, w.weatherCode)} · ${w.city}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            L10nHelper.weatherCompactSubLabel(context, w),
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: l.commonRefresh,
                      icon: RotationTransition(
                        turns: _weatherSpinCtrl,
                        child: const Icon(Icons.refresh_rounded, size: 18),
                      ),
                      onPressed: () async {
                        _weatherSpinCtrl.forward(from: 0);
                        final t0 = DateTime.now().millisecondsSinceEpoch;
                        UsageTelemetryService.instance.trackFeature('weather_refresh', 'tap');
                        final fresh = await WeatherService.getWeather(forceRefresh: true);
                        final dur = DateTime.now().millisecondsSinceEpoch - t0;
                        UsageTelemetryService.instance.trackFeature(
                          'weather_refresh',
                          fresh != null ? 'success' : 'fail',
                          durationMs: dur,
                        );
                        if (mounted && fresh != null) setState(() => _weather = fresh);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openWeatherCityQuickSheet() async {
    final manual = await WeatherService.getManualCity();
    if (!mounted) return;
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Color(0xFF26A69A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.weatherSheetTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.my_location_rounded, size: 16),
                    label: Text(l.weatherAutoLocate),
                    selected: manual == null,
                    onSelected: (_) async {
                      Navigator.pop(ctx);
                      await WeatherService.setAutoLocationMode();
                      final fresh = await WeatherService.getWeather(forceRefresh: true);
                      if (mounted && fresh != null) setState(() => _weather = fresh);
                    },
                  ),
                  ...WeatherService.presetCities.map((p) {
                    final sel = manual?.city == p.city;
                    return ChoiceChip(
                      label: Text(L10nHelper.weatherPresetLabel(context, p)),
                      selected: sel,
                      onSelected: (_) async {
                        Navigator.pop(ctx);
                        await WeatherService.setManualCity(city: p.city, lat: p.lat, lon: p.lon);
                        final fresh = await WeatherService.getWeather(forceRefresh: true);
                        if (mounted && fresh != null) setState(() => _weather = fresh);
                      },
                    );
                  }),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _open(const SettingsScreen());
                  },
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: Text(l.weatherSearchCity),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 校车下一班倒计时卡片（两行清晰展示完整站名 + 路线名 + 倒计时）
  Widget _busCard() {
    final l = context.l10n;
    final summaryText = L10nHelper.busDirectionSummary(
      context,
      rawDirection: _busDirection,
      nextTime: _busNextTime,
      minutesUntil: _busMinsUntil,
      isWeekend: _busIsWeekend,
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(const BusScheduleScreen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B5B84).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.directions_bus_rounded, color: Color(0xFF2B5B84)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.busHomeTitle(_busStop),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF7A22).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _busRouteName,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFFF7A22),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(summaryText, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  /// 手机传感器自动计步卡片（含目标进度环与热量折算）
  Widget _stepCounterCard() {
    final l = context.l10n;
    final ratio = (_todaySteps / (_stepGoal <= 0 ? 8000 : _stepGoal)).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFF26A69A).withValues(alpha: 0.16),
                    color: const Color(0xFF26A69A),
                  ),
                  const Center(child: Icon(Icons.directions_walk_rounded, color: Color(0xFF26A69A), size: 22)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.stepTitle(_todaySteps, _stepGoal),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    !_stepSupported
                        ? l.stepUnsupported
                        : (!_stepGranted
                            ? l.stepPermissionNeeded
                            : l.stepBurnedSummary(fmtNum(_stepBurnKcal))),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_stepSupported && !_stepGranted)
              FilledButton.tonal(
                onPressed: () async {
                  await StepService.requestPermission();
                  _load();
                },
                child: Text(l.stepAuthorize),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickMealInputCard() {
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFFF7A22)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _quickFoodCtrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitQuickFood(),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: l.homeQuickLogHint,
                ),
              ),
            ),
            _busyQuickAi
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : FilledButton.tonalIcon(
                    onPressed: _submitQuickFood,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: Text(l.homeAiQuickLog),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _quickHeroBanner() {
    Widget pill(IconData icon, String label, Color color, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final l = context.l10n;
    return Row(
      children: [
        pill(Icons.camera_alt_rounded, l.homeHeroSnapMeal, const Color(0xFFFF7A22), () => widget.onNavigate(2)),
        const SizedBox(width: 8),
        pill(Icons.fitness_center_rounded, l.homeHeroStartWorkout, const Color(0xFFEF5350), () => widget.onNavigate(3)),
        const SizedBox(width: 8),
        pill(Icons.monitor_weight_rounded, l.homeHeroLogWeight, const Color(0xFF2B5B84), () => _open(const BodyScreen())),
        const SizedBox(width: 8),
        pill(Icons.smart_toy_rounded, l.homeHeroAiCoach, const Color(0xFFAB47BC), () => widget.onNavigate(4)),
      ],
    );
  }

  Widget _profilePrompt() {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          child: const Icon(Icons.person_add_alt_1_rounded),
        ),
        title: Text(l.homeProfilePromptTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(l.homeProfilePromptSub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(OnboardingSheet(initialProfile: _profile, initialWeight: _latestWeight?.weight)),
      ),
    );
  }

  Widget _coursesCard() {
    final l = context.l10n;
    if (_todayCourses.isEmpty) {
      return Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x2226A69A),
            child: Icon(Icons.celebration_rounded, color: Color(0xFF26A69A)),
          ),
          title: Text(l.homeNoClassesToday),
        ),
      );
    }
    return Column(
      children: _todayCourses.map((c) {
        final st = ReminderService.sectionStartTime(c.startSection);
        final et = ReminderService.sectionEndTime(c.endSection);
        String two(int n) => n.toString().padLeft(2, '0');
        final startStr = '${two(st.hour)}:${two(st.minute)}';
        final endStr = '${two(et.hour)}:${two(et.minute)}';
        final color = Color(c.color);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(startStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(endStr, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(18),
                    border: Border(left: BorderSide(color: color, width: 5)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: color.withValues(alpha: 0.18),
                            child: Icon(courseIcon(c.name), size: 17, color: color),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('ACADEMIC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (c.location?.isNotEmpty == true)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.place_rounded, size: 14, color: color),
                                const SizedBox(width: 3),
                                Text(c.location!, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          if (c.teacher?.isNotEmpty == true)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_rounded, size: 14, color: Theme.of(context).colorScheme.outline),
                                const SizedBox(width: 3),
                                Text(c.teacher!, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _workoutCard() {
    final l = context.l10n;
    if (_todayWorkouts.isEmpty && _todayCardios.isEmpty) {
      return Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x22EF5350),
            child: Icon(Icons.fitness_center_rounded, color: Color(0xFFEF5350)),
          ),
          title: Text(l.homeNoWorkoutToday),
          subtitle: Text(l.homeNoWorkoutSub),
          trailing: FilledButton.tonal(onPressed: () => widget.onNavigate(3), child: Text(l.homeStartWorkoutBtn)),
        ),
      );
    }
    final cardioMins = _todayCardios.fold<double>(0, (s, c) => s + c.durationMinutes);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x2266BB6A),
          child: Icon(Icons.emoji_events_rounded, color: Color(0xFF66BB6A)),
        ),
        title: Text(
          [
            if (_todayWorkouts.isNotEmpty) l.homeStrengthSummary(_todayWorkouts.length, _todaySets),
            if (_todayCardios.isNotEmpty) l.homeCardioSummary(fmtNum(cardioMins)),
          ].join(' + '),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(l.homeWorkoutBurnSummary(fmtNum(_targets.workoutBurn))),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => widget.onNavigate(3),
      ),
    );
  }

  Widget _bodyCard() {
    final l = context.l10n;
    final w = _latestWeight?.weight;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x222B5B84),
          child: Icon(Icons.monitor_weight_rounded, color: Color(0xFF2B5B84)),
        ),
        title: Text(
          w != null ? l.homeWeightLabel(fmtNum(w, digits: 1)) : l.homeWeightNotLogged,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          l.homeBodyTargetSub(
            L10nHelper.goalLabel(context, _profile.goal),
            fmtNum(_targets.calories),
            fmtNum(_targets.protein),
          ),
        ),
        trailing: FilledButton.tonal(onPressed: () => _open(const BodyScreen()), child: Text(l.homeLogBodyBtn)),
        onTap: () => _open(const BodyScreen()),
      ),
    );
  }

  Widget _aiBannerCard() {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer.withValues(alpha: 0.55),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/icon/dafeiyu_mascot.png',
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => CircleAvatar(
              backgroundColor: cs.secondary,
              foregroundColor: cs.onSecondary,
              child: const Icon(Icons.smart_toy_rounded),
            ),
          ),
        ),
        title: Text(l.homeAiCoachBannerTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(l.homeAiCoachBannerSub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => widget.onNavigate(4),
      ),
    );
  }
}
