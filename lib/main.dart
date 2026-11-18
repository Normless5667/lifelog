import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'l10n/app_localizations.dart';
import 'screens/ai/ai_chat_screen.dart';
import 'screens/diet/diet_screen.dart';
import 'screens/home_screen.dart';
import 'screens/schedule/schedule_screen.dart';
import 'screens/workout/workout_list_screen.dart';
import 'services/app_prefs.dart';
import 'services/battery_probe_service.dart';
import 'services/usage_telemetry_service.dart';
import 'theme/app_theme.dart';
import 'utils/l10n_ext.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  await initializeDateFormatting('en_US');
  await AppPrefsController.instance.load();
  await BatteryProbeService.instance.init();
  await UsageTelemetryService.instance.init();
  runApp(const LifeLogApp());
}

class LifeLogApp extends StatelessWidget {
  const LifeLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefsController.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        return MaterialApp(
          onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appTitle,
          debugShowCheckedModeBanner: false,
          navigatorObservers: [BatteryProbeService.routeObserver],
          locale: prefs.localeOverride,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          themeMode: prefs.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(prefs.textScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabPageNames = ['home', 'schedule', 'diet', 'workout', 'ai'];

  void _goTo(int i) {
    if (i >= 0 && i < _tabPageNames.length) {
      UsageTelemetryService.instance.enterPage(_tabPageNames[i], source: 'tab');
    }
    setState(() => _index = i);
  }

  static Widget _navBadge(
    BuildContext context,
    IconData icon,
    Color moduleColor, {
    bool selected = false,
  }) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bg = selected
        ? AppColors.softBg(context, moduleColor, lightAlpha: 0.14, darkAlpha: 0.20)
        : Colors.transparent;
    final borderColor = selected
        ? AppColors.softBorder(context, moduleColor, lightAlpha: 0.24, darkAlpha: 0.32)
        : Colors.transparent;
    final iconColor = selected ? moduleColor : AppColors.textSecondary(context);

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.bPill,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Icon(icon, size: 22, color: iconColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefsController.instance;
    final l = context.l10n;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final pages = <Widget>[
          HomeScreen(key: UniqueKey(), onNavigate: _goTo),
          const ScheduleScreen(),
          const DietScreen(),
          const WorkoutListScreen(),
          const AiChatScreen(),
        ];

        final cToday = AppColors.moduleToday(context);
        final cSchedule = AppColors.moduleSchedule(context);
        final cDiet = AppColors.moduleDiet(context);
        final cWorkout = AppColors.moduleWorkout(context);
        final cAi = AppColors.moduleAi(context);

        return Scaffold(
          body: pages[_index],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.border(context).withValues(
                    alpha: AppColors.isDark(context) ? 0.65 : 0.85,
                  ),
                  width: 1,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _goTo,
              indicatorColor: Colors.transparent,
              destinations: [
                NavigationDestination(
                  icon: _navBadge(context, Icons.today_rounded, cToday),
                  selectedIcon: _navBadge(context, Icons.today_rounded, cToday, selected: true),
                  label: l.tabToday,
                ),
                NavigationDestination(
                  icon: _navBadge(context, Icons.calendar_month_rounded, cSchedule),
                  selectedIcon:
                      _navBadge(context, Icons.calendar_month_rounded, cSchedule, selected: true),
                  label: l.tabSchedule,
                ),
                NavigationDestination(
                  icon: _navBadge(context, Icons.restaurant_rounded, cDiet),
                  selectedIcon:
                      _navBadge(context, Icons.restaurant_rounded, cDiet, selected: true),
                  label: l.tabDiet,
                ),
                NavigationDestination(
                  icon: _navBadge(context, Icons.fitness_center_rounded, cWorkout),
                  selectedIcon:
                      _navBadge(context, Icons.fitness_center_rounded, cWorkout, selected: true),
                  label: l.tabWorkout,
                ),
                NavigationDestination(
                  icon: _navBadge(context, Icons.smart_toy_rounded, cAi),
                  selectedIcon: _navBadge(context, Icons.smart_toy_rounded, cAi, selected: true),
                  label: l.tabAi,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
