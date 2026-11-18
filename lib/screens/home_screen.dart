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

/// 今日仪表盘（生活助手 v2.0 视觉重写）：
/// - 统一引用 AppColors / AppTypography / AppSpacing / AppRadius / AppShadows
/// - 向下滚动自动收起悬浮按钮（避免遮挡底部内容）
/// - 深浅色自适应低饱和度语义模块色与高对比度数字焦点排版
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
  bool _fabVisible = true;
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
    final todayCourses =
        courses.where((c) => c.weekday == wd && c.activeInWeek(week)).toList()
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
            builder: (_) => OnboardingSheet(
              initialProfile: profile,
              initialWeight: weight?.weight,
            ),
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
      UsageTelemetryService.instance.trackFeature(
        'ai_log',
        'fail',
        durationMs: dur,
        errorMsg: '$e',
      );
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
      builder: (ctx) {
        Widget sheetItem({
          required IconData icon,
          required Color color,
          required String title,
          required VoidCallback onTap,
        }) {
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxs,
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.softBg(ctx, color, lightAlpha: 0.12, darkAlpha: 0.18),
                borderRadius: AppRadius.bMd,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(title, style: AppTypography.subtitle(ctx)),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary(ctx),
            ),
            onTap: onTap,
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, color: AppColors.accent(ctx), size: 22),
                      const SizedBox(width: AppSpacing.sm),
                      Text(l.homeQuickRecord, style: AppTypography.sectionTitle(ctx)),
                    ],
                  ),
                ),
                sheetItem(
                  icon: Icons.restaurant_rounded,
                  color: AppColors.moduleDiet(ctx),
                  title: l.homeQuickDiet,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onNavigate(2);
                  },
                ),
                sheetItem(
                  icon: Icons.fitness_center_rounded,
                  color: AppColors.moduleWorkout(ctx),
                  title: l.homeQuickWorkout,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onNavigate(3);
                  },
                ),
                sheetItem(
                  icon: Icons.monitor_weight_rounded,
                  color: AppColors.moduleBody(ctx),
                  title: l.homeQuickWeight,
                  onTap: () {
                    Navigator.pop(ctx);
                    _open(const BodyScreen());
                  },
                ),
                sheetItem(
                  icon: Icons.directions_bus_rounded,
                  color: AppColors.moduleSchedule(ctx),
                  title: l.homeQuickBus,
                  onTap: () {
                    Navigator.pop(ctx);
                    _open(const BusScheduleScreen());
                  },
                ),
                sheetItem(
                  icon: Icons.widgets_rounded,
                  color: AppColors.teal(ctx),
                  title: l.widgetGuideTitle,
                  onTap: () {
                    Navigator.pop(ctx);
                    showAddHomeWidgetGuideDialog(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _onScrollNotification(ScrollUpdateNotification n) {
    final dy = n.scrollDelta ?? 0;
    if (dy > 6 && _fabVisible && n.metrics.pixels > 40) {
      setState(() => _fabVisible = false);
    } else if ((dy < -6 || n.metrics.pixels <= 20) && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
    return false;
  }

  Widget _appBarActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceSubtle(context),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.all(AppSpacing.sm),
        ),
        icon: Icon(icon, size: 19, color: AppColors.textPrimary(context)),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final l = context.l10n;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final primary = AppColors.primary(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, primary, lightAlpha: 0.12, darkAlpha: 0.20),
                borderRadius: AppRadius.bSm,
                border: Border.all(color: AppColors.softBorder(context, primary)),
              ),
              child: Icon(Icons.wb_sunny_rounded, size: 18, color: primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                '${now.month}/${now.day} ${L10nHelper.weekdayLabel(context, now.weekday)}',
                style: AppTypography.pageTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          _appBarActionButton(
            icon: Icons.directions_bus_rounded,
            tooltip: l.busBoardTitle,
            onPressed: () => _open(const BusScheduleScreen()),
          ),
          _appBarActionButton(
            icon: Icons.monitor_weight_rounded,
            tooltip: l.bodyTitle,
            onPressed: () => _open(const BodyScreen()),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: _appBarActionButton(
              icon: Icons.settings_rounded,
              tooltip: l.settingsTitle,
              onPressed: () => _open(const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: AnimatedSlide(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: _fabVisible ? Offset.zero : const Offset(0, 2.0),
        child: AnimatedOpacity(
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
          opacity: _fabVisible ? 1.0 : 0.0,
          child: FloatingActionButton.small(
            onPressed: _openQuickRecordMenu,
            tooltip: l.homeQuickRecord,
            elevation: 2,
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.bLg),
            child: const Icon(Icons.add_rounded, size: 24),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onScrollNotification,
                child: ListView(
                  padding: AppSpacing.pagePadding,
                  children: [
                    _streakAndWeatherSection(),
                    const SizedBox(height: AppSpacing.md),
                    _busCard(),
                    const SizedBox(height: AppSpacing.md),
                    _quickHeroBanner(),
                    const SizedBox(height: AppSpacing.md),
                    _quickMealInputCard(),
                    if (!_hasProfile) ...[
                      const SizedBox(height: AppSpacing.md),
                      _profilePrompt(),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    CalorieSummaryCard(
                      totals: _totals,
                      targets: _targets,
                      onTap: () => widget.onNavigate(2),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _stepCounterCard(),
                    SectionTitle(
                      _week > 0 ? l.homeTodayClassesWeek(_week) : l.homeTodayClasses,
                      icon: Icons.school_rounded,
                      iconColor: AppColors.moduleSchedule(context),
                      trailing: TextButton.icon(
                        onPressed: () => widget.onNavigate(1),
                        icon: const Icon(Icons.calendar_view_week_rounded, size: 15),
                        label: Text(l.homeAllSchedule),
                      ),
                    ),
                    _coursesCard(),
                    SectionTitle(
                      l.homeTodayWorkoutTitle,
                      icon: Icons.fitness_center_rounded,
                      iconColor: AppColors.moduleWorkout(context),
                      trailing: TextButton.icon(
                        onPressed: () => widget.onNavigate(3),
                        icon: const Icon(Icons.chevron_right_rounded, size: 18),
                        label: Text(l.homeGoWorkout),
                      ),
                    ),
                    _workoutCard(),
                    SectionTitle(
                      l.homeBodyStatus,
                      icon: Icons.favorite_rounded,
                      iconColor: AppColors.moduleBody(context),
                    ),
                    _bodyCard(),
                    const SizedBox(height: AppSpacing.lg),
                    _aiBannerCard(),
                  ],
                ),
              ),
            ),
    );
  }

  /// 标题下方：打卡连续天数激励胶囊 + 两行精简天气卡片
  Widget _streakAndWeatherSection() {
    final w = _weather;
    final l = context.l10n;
    final accent = AppColors.accent(context);
    final scheduleColor = AppColors.moduleSchedule(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, accent, lightAlpha: 0.12, darkAlpha: 0.18),
                  borderRadius: AppRadius.bPill,
                  border: Border.all(color: AppColors.softBorder(context, accent)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department_rounded, size: 15, color: accent),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l.homeStreakDays(_streak),
                      style: AppTypography.badge(context, color: accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _streak > 0 ? l.homeStreakKeepGoing : l.homeStreakStartHint,
                  style: AppTypography.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (w != null)
          SurfaceCard(
            onTap: _openWeatherCityQuickSheet,
            padding: AppSpacing.cardCompactPadding,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, scheduleColor),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Text(w.emoji, style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${fmtNum(w.temperature)}°',
                            style: AppTypography.metricLarge(context),
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Expanded(
                            child: Text(
                              '${L10nHelper.weatherConditionLabel(context, w.weatherCode)} · ${w.city}',
                              style: AppTypography.subtitle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        L10nHelper.weatherCompactSubLabel(context, w),
                        style: AppTypography.caption(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l.commonRefresh,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceSubtle(context),
                    minimumSize: const Size(32, 32),
                    padding: const EdgeInsets.all(6),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.bSm),
                  ),
                  icon: RotationTransition(
                    turns: _weatherSpinCtrl,
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: AppColors.textSecondary(context),
                    ),
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on_rounded, color: AppColors.teal(ctx)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l.weatherSheetTitle,
                      style: AppTypography.cardTitle(ctx),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
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
                        await WeatherService.setManualCity(
                          city: p.city,
                          lat: p.lat,
                          lon: p.lon,
                        );
                        final fresh = await WeatherService.getWeather(forceRefresh: true);
                        if (mounted && fresh != null) setState(() => _weather = fresh);
                      },
                    );
                  }),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
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
    final primary = AppColors.primary(context);
    final accent = AppColors.accent(context);
    final summaryText = L10nHelper.busDirectionSummary(
      context,
      rawDirection: _busDirection,
      nextTime: _busNextTime,
      minutesUntil: _busMinsUntil,
      isWeekend: _busIsWeekend,
    );

    return SurfaceCard(
      onTap: () => _open(const BusScheduleScreen()),
      padding: AppSpacing.cardCompactPadding,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, primary, lightAlpha: 0.12, darkAlpha: 0.18),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.directions_bus_rounded, color: primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.busHomeTitle(_busStop),
                  style: AppTypography.cardTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm - 1,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.softBg(context, accent),
                        borderRadius: AppRadius.bXs,
                      ),
                      child: Text(
                        _busRouteName,
                        style: AppTypography.badge(context, color: accent).copyWith(fontSize: 10),
                      ),
                    ),
                    Text(
                      summaryText,
                      style: AppTypography.bodySecondary(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textTertiary(context),
          ),
        ],
      ),
    );
  }

  /// 手机传感器自动计步卡片（含目标进度环与热量折算）
  Widget _stepCounterCard() {
    final l = context.l10n;
    final teal = AppColors.teal(context);
    final ratio = (_todaySteps / (_stepGoal <= 0 ? 8000 : _stepGoal)).clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SurfaceCard(
      padding: AppSpacing.cardCompactPadding,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: ratio),
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, val, _) => CircularProgressIndicator(
                    value: val,
                    strokeWidth: 5.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: AppColors.softBg(context, teal, lightAlpha: 0.14, darkAlpha: 0.20),
                    color: teal,
                  ),
                ),
                Center(
                  child: Icon(Icons.directions_walk_rounded, color: teal, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.stepTitle(_todaySteps, _stepGoal),
                  style: AppTypography.cardTitle(context),
                ),
                const SizedBox(height: 3),
                Text(
                  !_stepSupported
                      ? l.stepUnsupported
                      : (!_stepGranted
                          ? l.stepPermissionNeeded
                          : l.stepBurnedSummary(fmtNum(_stepBurnKcal))),
                  style: AppTypography.bodySecondary(context),
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
    );
  }

  Widget _quickMealInputCard() {
    final l = context.l10n;
    final accent = AppColors.accent(context);
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, accent),
              borderRadius: AppRadius.bSm,
            ),
            child: Icon(Icons.bolt_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _quickFoodCtrl,
              textInputAction: TextInputAction.send,
              style: AppTypography.body(context, color: AppColors.textPrimary(context)),
              onSubmitted: (_) => _submitQuickFood(),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                hintText: l.homeQuickLogHint,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _busyQuickAi
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : FilledButton.tonalIcon(
                  onPressed: _submitQuickFood,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.softBg(
                      context,
                      accent,
                      lightAlpha: 0.14,
                      darkAlpha: 0.22,
                    ),
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                  label: Text(l.homeAiQuickLog),
                ),
        ],
      ),
    );
  }

  /// 四个模块快捷入口：统一圆角（卡片 16dp、图标容器 12dp）、统一阴影与低饱和度深色适配
  Widget _quickHeroBanner() {
    Widget pill(IconData icon, String label, Color moduleColor, VoidCallback onTap) {
      return Expanded(
        child: ScaleTap(
          onTap: onTap,
          borderRadius: AppRadius.bLg,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: AppRadius.bLg,
              border: Border.all(
                color: AppColors.border(context).withValues(
                  alpha: AppColors.isDark(context) ? 0.75 : 0.85,
                ),
              ),
              boxShadow: AppShadows.subtle(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(
                      context,
                      moduleColor,
                      lightAlpha: 0.12,
                      darkAlpha: 0.18,
                    ),
                    borderRadius: AppRadius.bMd,
                    border: Border.all(
                      color: AppColors.softBorder(
                        context,
                        moduleColor,
                        lightAlpha: 0.20,
                        darkAlpha: 0.28,
                      ),
                    ),
                  ),
                  child: Icon(icon, color: moduleColor, size: 22),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  style: AppTypography.badge(
                    context,
                    color: AppColors.textPrimary(context),
                  ).copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
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
        pill(
          Icons.camera_alt_rounded,
          l.homeHeroSnapMeal,
          AppColors.moduleDiet(context),
          () => widget.onNavigate(2),
        ),
        const SizedBox(width: AppSpacing.sm),
        pill(
          Icons.fitness_center_rounded,
          l.homeHeroStartWorkout,
          AppColors.moduleWorkout(context),
          () => widget.onNavigate(3),
        ),
        const SizedBox(width: AppSpacing.sm),
        pill(
          Icons.monitor_weight_rounded,
          l.homeHeroLogWeight,
          AppColors.moduleBody(context),
          () => _open(const BodyScreen()),
        ),
        const SizedBox(width: AppSpacing.sm),
        pill(
          Icons.smart_toy_rounded,
          l.homeHeroAiCoach,
          AppColors.moduleAi(context),
          () => widget.onNavigate(4),
        ),
      ],
    );
  }

  Widget _profilePrompt() {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    return SurfaceCard(
      backgroundColor: AppColors.softBg(context, primary, lightAlpha: 0.08, darkAlpha: 0.14),
      borderColor: AppColors.softBorder(context, primary),
      padding: AppSpacing.cardCompactPadding,
      onTap: () => _open(
        OnboardingSheet(initialProfile: _profile, initialWeight: _latestWeight?.weight),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: AppRadius.bMd,
            ),
            child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.homeProfilePromptTitle, style: AppTypography.cardTitle(context)),
                const SizedBox(height: 2),
                Text(l.homeProfilePromptSub, style: AppTypography.bodySecondary(context)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary(context)),
        ],
      ),
    );
  }

  Widget _coursesCard() {
    final l = context.l10n;
    final teal = AppColors.teal(context);
    if (_todayCourses.isEmpty) {
      return SurfaceCard(
        padding: AppSpacing.cardCompactPadding,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, teal),
                borderRadius: AppRadius.bMd,
              ),
              child: Icon(Icons.celebration_rounded, color: teal, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(l.homeNoClassesToday, style: AppTypography.subtitle(context)),
            ),
          ],
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
        final color = AppColors.adaptForDark(context, Color(c.color));

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      startStr,
                      style: AppTypography.metricMedium(context).copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(endStr, style: AppTypography.caption(context)),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: AppRadius.bLg,
                    border: Border.all(
                      color: AppColors.border(context).withValues(
                        alpha: AppColors.isDark(context) ? 0.75 : 0.85,
                      ),
                    ),
                    boxShadow: AppShadows.card(context),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.bLg,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: color, width: 4)),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppColors.softBg(context, color),
                                  borderRadius: AppRadius.bSm,
                                ),
                                child: Icon(courseIcon(c.name), size: 16, color: color),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: AppTypography.subtitle(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.softBg(context, color),
                                  borderRadius: AppRadius.bPill,
                                ),
                                child: Text(
                                  'ACADEMIC',
                                  style: AppTypography.badge(context, color: color)
                                      .copyWith(fontSize: 9.5),
                                ),
                              ),
                            ],
                          ),
                          if (c.location?.isNotEmpty == true ||
                              c.teacher?.isNotEmpty == true) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.md,
                              runSpacing: AppSpacing.xs,
                              children: [
                                if (c.location?.isNotEmpty == true)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.place_rounded, size: 13, color: color),
                                      const SizedBox(width: 3),
                                      Text(
                                        c.location!,
                                        style: AppTypography.bodySecondary(context),
                                      ),
                                    ],
                                  ),
                                if (c.teacher?.isNotEmpty == true)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person_rounded,
                                        size: 13,
                                        color: AppColors.textTertiary(context),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        c.teacher!,
                                        style: AppTypography.bodySecondary(context),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
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
    final workoutColor = AppColors.moduleWorkout(context);
    final successColor = AppColors.success(context);

    if (_todayWorkouts.isEmpty && _todayCardios.isEmpty) {
      return SurfaceCard(
        padding: AppSpacing.cardCompactPadding,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, workoutColor),
                borderRadius: AppRadius.bMd,
              ),
              child: Icon(Icons.fitness_center_rounded, color: workoutColor, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.homeNoWorkoutToday, style: AppTypography.cardTitle(context)),
                  const SizedBox(height: 2),
                  Text(l.homeNoWorkoutSub, style: AppTypography.bodySecondary(context)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: () => widget.onNavigate(3),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.softBg(
                  context,
                  workoutColor,
                  lightAlpha: 0.12,
                  darkAlpha: 0.20,
                ),
                foregroundColor: workoutColor,
              ),
              child: Text(l.homeStartWorkoutBtn),
            ),
          ],
        ),
      );
    }

    final cardioMins = _todayCardios.fold<double>(0, (s, c) => s + c.durationMinutes);
    return SurfaceCard(
      onTap: () => widget.onNavigate(3),
      padding: AppSpacing.cardCompactPadding,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, successColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.emoji_events_rounded, color: successColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (_todayWorkouts.isNotEmpty)
                      l.homeStrengthSummary(_todayWorkouts.length, _todaySets),
                    if (_todayCardios.isNotEmpty) l.homeCardioSummary(fmtNum(cardioMins)),
                  ].join(' + '),
                  style: AppTypography.cardTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  l.homeWorkoutBurnSummary(fmtNum(_targets.workoutBurn)),
                  style: AppTypography.bodySecondary(context),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary(context)),
        ],
      ),
    );
  }

  Widget _bodyCard() {
    final l = context.l10n;
    final w = _latestWeight?.weight;
    final bodyColor = AppColors.moduleBody(context);

    return SurfaceCard(
      onTap: () => _open(const BodyScreen()),
      padding: AppSpacing.cardCompactPadding,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, bodyColor),
              borderRadius: AppRadius.bMd,
            ),
            child: Icon(Icons.monitor_weight_rounded, color: bodyColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w != null ? l.homeWeightLabel(fmtNum(w, digits: 1)) : l.homeWeightNotLogged,
                  style: AppTypography.cardTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  l.homeBodyTargetSub(
                    L10nHelper.goalLabel(context, _profile.goal),
                    fmtNum(_targets.calories),
                    fmtNum(_targets.protein),
                  ),
                  style: AppTypography.bodySecondary(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.tonal(
            onPressed: () => _open(const BodyScreen()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softBg(
                context,
                bodyColor,
                lightAlpha: 0.12,
                darkAlpha: 0.20,
              ),
              foregroundColor: bodyColor,
            ),
            child: Text(l.homeLogBodyBtn),
          ),
        ],
      ),
    );
  }

  Widget _aiBannerCard() {
    final l = context.l10n;
    final aiColor = AppColors.moduleAi(context);

    return SurfaceCard(
      onTap: () => widget.onNavigate(4),
      backgroundColor: AppColors.softBg(context, aiColor, lightAlpha: 0.08, darkAlpha: 0.14),
      borderColor: AppColors.softBorder(context, aiColor, lightAlpha: 0.20, darkAlpha: 0.28),
      padding: AppSpacing.cardCompactPadding,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.bMd,
            child: Image.asset(
              'assets/icon/dafeiyu_mascot.png',
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, aiColor, lightAlpha: 0.16, darkAlpha: 0.24),
                  borderRadius: AppRadius.bMd,
                ),
                child: Icon(Icons.smart_toy_rounded, color: aiColor),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.homeAiCoachBannerTitle, style: AppTypography.cardTitle(context)),
                const SizedBox(height: 2),
                Text(l.homeAiCoachBannerSub, style: AppTypography.bodySecondary(context)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: aiColor),
        ],
      ),
    );
  }
}
