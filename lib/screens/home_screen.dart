import 'package:flutter/material.dart';

import '../db/repo.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/app_prefs.dart';
import '../services/bus_service.dart';
import '../services/nutrition.dart';
import '../services/reminder_service.dart';
import '../services/step_service.dart';
import '../services/targets.dart';
import '../services/weather_service.dart';
import '../utils/date_utils.dart';
import '../widgets/common.dart';
import 'body/body_screen.dart';
import 'body/onboarding_sheet.dart';
import 'diet/food_confirm_sheet.dart';
import 'schedule/bus_schedule_screen.dart';
import 'settings/settings_screen.dart';

/// 今日仪表盘 v1.2（生活助手）：
/// - Open-Meteo 实时天气卡片（30分钟缓存）
/// - Hai Ba Trung 校车下一班倒计时卡片（点按选常用站点）
/// - 硬件级自动计步器进度环（TYPE_STEP_COUNTER）
/// - 连续打卡天数 (Streak) + 一句话 AI 速记饮食 + 右下角快捷记录 FAB
/// - 自动同步更新安卓桌面小组件 (AppWidget)
class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigate;
  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _quickFoodCtrl = TextEditingController();
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

  // v1.2/v1.3 新增：天气、校车路线、计步器状态
  WeatherInfo? _weather;
  String _busRouteName = 'BUV · Hai Ba Trung Route';
  String _busStop = 'TIMES CITY';
  String _busDirection = '';
  String _busNextTime = '--:--';
  int _busMinsUntil = -1;
  bool _stepSupported = true;
  bool _stepGranted = true;
  int _todaySteps = 0;
  int _stepGoal = 8000;
  double _stepBurnKcal = 0;

  @override
  void initState() {
    super.initState();
    _load(checkOnboarding: true);
  }

  @override
  void dispose() {
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
    final remKcal = (targets.calories - totals.calories).round();
    final firstCourse = todayCourses.isEmpty
        ? '📅 今日无课'
        : '📅 ${ReminderService.formatRange(todayCourses.first.startSection, todayCourses.first.endSection)} ${todayCourses.first.name}';
    ReminderService.updateHomeWidget(
      courseLine: firstCourse,
      calorieLine: '🔥 剩余热量：$remKcal kcal（已吃 ${totals.calories.round()}）',
      stepLine: '👟 今日步数：${stepState.todaySteps} / ${stepState.goal} 步',
    );
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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
      if (saved == true) {
        _quickFoodCtrl.clear();
        _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyQuickAi = false);
      showAiError(context, e, onOpenSettings: () => _open(const SettingsScreen()));
    }
  }

  void _openQuickRecordMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('⚡ 快速记录', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x22FF7A22),
                child: Icon(Icons.restaurant_rounded, color: Color(0xFFFF7A22)),
              ),
              title: const Text('快速记饮食 / 拍照识热量'),
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
              title: const Text('快速开始训练 / 记有氧'),
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
              title: const Text('快速记今日体重'),
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
              title: const Text('查看校车时刻表与换站'),
              onTap: () {
                Navigator.pop(ctx);
                _open(const BusScheduleScreen());
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
    final prefs = AppPrefsController.instance;
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
            Text('${now.month}月${now.day}日 ${weekdayNames[now.weekday - 1]}'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7A22).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_rounded, size: 15, color: Color(0xFFFF7A22)),
                  const SizedBox(width: 2),
                  Text(
                    prefs.tr('连续 $_streak 天', '$_streak d'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF7A22)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: prefs.tr('校车时刻表', 'Bus Schedule'),
            icon: const Icon(Icons.directions_bus_rounded),
            onPressed: () => _open(const BusScheduleScreen()),
          ),
          IconButton(
            tooltip: prefs.tr('身体数据', 'Body Data'),
            icon: const Icon(Icons.monitor_weight_rounded),
            onPressed: () => _open(const BodyScreen()),
          ),
          IconButton(
            tooltip: prefs.tr('设置', 'Settings'),
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openQuickRecordMenu,
        tooltip: '快捷记录',
        backgroundColor: const Color(0xFFFF7A22),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                children: [
                  _weatherAndBusRow(),
                  const SizedBox(height: 8),
                  _quickHeroBanner(),
                  const SizedBox(height: 8),
                  _quickMealInputCard(),
                  if (!_hasProfile) _profilePrompt(),
                  CalorieSummaryCard(totals: _totals, targets: _targets, onTap: () => widget.onNavigate(2)),
                  _stepCounterCard(),
                  SectionTitle(
                    _week > 0
                        ? prefs.tr('今日课程 · 第 $_week 周', 'Today\'s Classes · Week $_week')
                        : prefs.tr('今日课程', 'Today\'s Classes'),
                    icon: Icons.school_rounded,
                    iconColor: const Color(0xFF2B5B84),
                    trailing: TextButton.icon(
                      onPressed: () => widget.onNavigate(1),
                      icon: const Icon(Icons.calendar_view_week_rounded, size: 16),
                      label: Text(prefs.tr('全部课表', 'All Schedule')),
                    ),
                  ),
                  _coursesCard(),
                  SectionTitle(
                    prefs.tr('今日训练与有氧汇总', 'Today\'s Workout & Cardio'),
                    icon: Icons.fitness_center_rounded,
                    iconColor: const Color(0xFFEF5350),
                    trailing: TextButton.icon(
                      onPressed: () => widget.onNavigate(3),
                      icon: const Icon(Icons.chevron_right, size: 18),
                      label: Text(prefs.tr('去训练', 'Workout')),
                    ),
                  ),
                  _workoutCard(),
                  SectionTitle(
                    prefs.tr('身体状态', 'Body Status'),
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

  /// 顶部天气卡片 + 校车下一班倒计时卡片
  Widget _weatherAndBusRow() {
    final w = _weather;
    return Column(
      children: [
        if (w != null)
          Card(
            child: ListTile(
              leading: Text(w.emoji, style: const TextStyle(fontSize: 30)),
              title: Text(
                '${w.city} · ${fmtNum(w.temperature)}°C ${w.conditionText}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(w.summaryLine, style: const TextStyle(fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: () async {
                  final fresh = await WeatherService.getWeather(forceRefresh: true);
                  if (mounted && fresh != null) setState(() => _weather = fresh);
                },
              ),
            ),
          ),
        Card(
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${AppPrefsController.instance.tr('校车', 'Bus')} · $_busStop',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF7A22).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _busRouteName,
                                style: const TextStyle(fontSize: 10, color: Color(0xFFFF7A22), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _busMinsUntil >= 0
                              ? '$_busDirection · 下一班 $_busNextTime，还有 $_busMinsUntil 分钟'
                              : _busDirection,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 手机传感器自动计步卡片（含目标进度环与热量折算）
  Widget _stepCounterCard() {
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
                    '今日自动步数：$_todaySteps / $_stepGoal 步',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    !_stepSupported
                        ? '当前设备无硬件计步传感器（可在训练页手动记走路/跑步）'
                        : (!_stepGranted
                            ? '需要授予「身体活动」权限才能读取手机计步传感器'
                            : '步数折算消耗 +${fmtNum(_stepBurnKcal)} kcal（已自动计入今日饮食额度）'),
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
                child: const Text('授权计步'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickMealInputCard() {
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
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: '一句话速记今天吃了什么（如：一碗牛肉面加个蛋）',
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
                    label: const Text('AI速记'),
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
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }

    final prefs = AppPrefsController.instance;
    return Row(
      children: [
        pill(Icons.camera_alt_rounded, prefs.tr('拍美食算热量', 'Snap Meal'), const Color(0xFFFF7A22), () => widget.onNavigate(2)),
        const SizedBox(width: 8),
        pill(Icons.fitness_center_rounded, prefs.tr('开始训练计时', 'Start Workout'), const Color(0xFFEF5350), () => widget.onNavigate(3)),
        const SizedBox(width: 8),
        pill(Icons.monitor_weight_rounded, prefs.tr('记今日体重', 'Log Weight'), const Color(0xFF2B5B84), () => _open(const BodyScreen())),
        const SizedBox(width: 8),
        pill(Icons.smart_toy_rounded, prefs.tr('AI 定制计划', 'AI Coach'), const Color(0xFFAB47BC), () => widget.onNavigate(4)),
      ],
    );
  }

  Widget _profilePrompt() {
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
        title: const Text('完善个人运动与身体问卷', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('30秒填好身高、目标与器械条件，自动计算动态 TDEE'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(OnboardingSheet(initialProfile: _profile, initialWeight: _latestWeight?.weight)),
      ),
    );
  }

  Widget _coursesCard() {
    if (_todayCourses.isEmpty) {
      return const Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(0x2226A69A),
            child: Icon(Icons.celebration_rounded, color: Color(0xFF26A69A)),
          ),
          title: Text('今天没有课，好好休息或去锻炼吧！'),
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
    if (_todayWorkouts.isEmpty && _todayCardios.isEmpty) {
      return Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x22EF5350),
            child: Icon(Icons.fitness_center_rounded, color: Color(0xFFEF5350)),
          ),
          title: const Text('今天还没有训练或有氧记录'),
          subtitle: const Text('训练消耗会自动叠加到今日可摄入热量额度'),
          trailing: FilledButton.tonal(onPressed: () => widget.onNavigate(3), child: const Text('开练')),
        ),
      );
    }
    final strengthMins = _todayWorkouts.fold<int>(0, (sum, w) {
      if (w.endTime == null) return sum;
      return sum + ((w.endTime! - w.startTime) ~/ 60000);
    });
    final cardioMins = _todayCardios.fold<double>(0, (s, c) => s + c.durationMinutes);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x2266BB6A),
          child: Icon(Icons.emoji_events_rounded, color: Color(0xFF66BB6A)),
        ),
        title: Text(
          [
            if (_todayWorkouts.isNotEmpty) '力量 ${_todayWorkouts.length} 次（$_todaySets 组）',
            if (_todayCardios.isNotEmpty) '有氧 ${fmtNum(cardioMins)} 分钟',
          ].join(' + '),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '今日活动与训练总消耗约 +${fmtNum(_targets.workoutBurn)} kcal${strengthMins > 0 ? ' · 力量耗时 $strengthMins 分钟' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => widget.onNavigate(3),
      ),
    );
  }

  Widget _bodyCard() {
    final w = _latestWeight?.weight;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x222B5B84),
          child: Icon(Icons.monitor_weight_rounded, color: Color(0xFF2B5B84)),
        ),
        title: Text(
          w == null
              ? '还没有体重记录'
              : '当前体重 ${fmtNum(w, digits: 1)} kg${_profile.targetWeight != null ? '（目标 ${fmtNum(_profile.targetWeight!, digits: 1)} kg）' : ''}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: w == null
            ? const Text('点击记录体重、体脂率或腰围')
            : Text('BMI ${fmtNum(Nutrition.bmi(_profile.height, w), digits: 1)}'
                '（${Nutrition.bmiLabel(Nutrition.bmi(_profile.height, w))}）· 静息 TDEE ${fmtNum(Nutrition.tdee(_profile, w))} kcal'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(const BodyScreen()),
      ),
    );
  }

  Widget _aiBannerCard() {
    return InkWell(
      onTap: () => widget.onNavigate(4),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E3C58), Color(0xFF2B5B84)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('assets/icon/dafeiyu_mascot.png', width: 46, height: 46, fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DeepSeek AI 私人健康管家',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('结合今日天气、课表、步数与热量缺口生成专属计划',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}
