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
import 'widgets/m3_sliding_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 限制 Flutter 图片解码缓存上限（32 MB / 60 张），避免食物拍照缩略图导致常驻内存膨胀
  PaintingBinding.instance.imageCache.maximumSize = 60;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
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
          darkTheme: prefs.isMidnight ? AppTheme.midnight() : AppTheme.dark(),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(prefs.textScale),
              ),
              child: MidnightBackdropLayer(
                enabled: prefs.isMidnight,
                child: child ?? const SizedBox.shrink(),
              ),
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
  int _prevIndex = 0;

  static const _tabPageNames = ['home', 'schedule', 'diet', 'workout', 'ai'];

  void _goTo(int i) {
    if (i == _index) return;
    if (i >= 0 && i < _tabPageNames.length) {
      UsageTelemetryService.instance.enterPage(_tabPageNames[i], source: 'tab');
    }
    setState(() {
      _prevIndex = _index;
      _index = i;
    });
  }

  Widget _buildTabPage(int index) {
    switch (index) {
      case 0:
        return HomeScreen(key: const ValueKey('tab_home'), onNavigate: _goTo);
      case 1:
        return const ScheduleScreen(key: ValueKey('tab_schedule'));
      case 2:
        return const DietScreen(key: ValueKey('tab_diet'));
      case 3:
        return const WorkoutListScreen(key: ValueKey('tab_workout'));
      case 4:
        return const AiChatScreen(key: ValueKey('tab_ai'));
      default:
        return HomeScreen(key: const ValueKey('tab_home'), onNavigate: _goTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefsController.instance;
    final l = context.l10n;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isForward = _index >= _prevIndex;

    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final cToday = AppColors.moduleToday(context);
        final cSchedule = AppColors.moduleSchedule(context);
        final cDiet = AppColors.moduleDiet(context);
        final cWorkout = AppColors.moduleWorkout(context);
        final cAi = AppColors.moduleAi(context);

        return Scaffold(
          body: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : AppMotion.pageTransition,
            reverseDuration: reduceMotion ? Duration.zero : AppMotion.short4,
            switchInCurve: AppMotion.standardCurve,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              final isIncoming = child.key == ValueKey<int>(_index);
              final sign = isForward ? 1.0 : -1.0;
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, c) {
                  final t = animation.value;
                  final dx = isIncoming
                      ? sign * AppMotion.subtleSlidePx * (1.0 - t)
                      : -sign * (AppMotion.subtleSlidePx * 0.5) * (1.0 - t);
                  return Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(dx, 0),
                      child: c,
                    ),
                  );
                },
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_index),
              child: _buildTabPage(_index),
            ),
          ),
          bottomNavigationBar: M3SlidingNavBar(
            selectedIndex: _index,
            onDestinationSelected: _goTo,
            destinations: [
              M3NavDestination(
                icon: Icons.today_rounded,
                label: l.tabToday,
                color: cToday,
              ),
              M3NavDestination(
                icon: Icons.calendar_month_rounded,
                label: l.tabSchedule,
                color: cSchedule,
              ),
              M3NavDestination(
                icon: Icons.restaurant_rounded,
                label: l.tabDiet,
                color: cDiet,
              ),
              M3NavDestination(
                icon: Icons.fitness_center_rounded,
                label: l.tabWorkout,
                color: cWorkout,
              ),
              M3NavDestination(
                icon: Icons.smart_toy_rounded,
                label: l.tabAi,
                color: cAi,
              ),
            ],
          ),
        );
      },
    );
  }
}
