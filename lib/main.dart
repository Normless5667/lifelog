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
import 'utils/l10n_ext.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  await initializeDateFormatting('en_US');
  await AppPrefsController.instance.load();
  await BatteryProbeService.instance.init();
  runApp(const LifeLogApp());
}

class LifeLogApp extends StatelessWidget {
  const LifeLogApp({super.key});

  /// Keep 风格配色与大圆角卡片设计语言（主色深蓝 #2B5B84 + 活力强调橙 #FF7A22，卡片 20dp，按钮 16dp，输入框 12dp）
  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final cs = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2B5B84),
      primary: isDark ? const Color(0xFF64B5F6) : const Color(0xFF2B5B84),
      secondary: const Color(0xFFFF7A22),
      tertiary: const Color(0xFF26A69A),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? const Color(0xFF12161F) : const Color(0xFFF6F8FB),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        color: isDark ? const Color(0xFF1C222E) : Colors.white,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 1.8),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF171C26) : Colors.white,
        isDense: true,
      ),
    );
  }

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
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
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

  void _goTo(int i) => setState(() => _index = i);

  static Widget _navBadge(IconData icon, Color color, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 22, color: selected ? Colors.white : color),
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
        return Scaffold(
          body: pages[_index],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _goTo,
            indicatorColor: Colors.transparent,
            destinations: [
              NavigationDestination(
                icon: _navBadge(Icons.today_rounded, const Color(0xFF2B5B84)),
                selectedIcon: _navBadge(Icons.today_rounded, const Color(0xFF2B5B84), selected: true),
                label: l.tabToday,
              ),
              NavigationDestination(
                icon: _navBadge(Icons.calendar_month_rounded, const Color(0xFF42A5F5)),
                selectedIcon: _navBadge(Icons.calendar_month_rounded, const Color(0xFF42A5F5), selected: true),
                label: l.tabSchedule,
              ),
              NavigationDestination(
                icon: _navBadge(Icons.restaurant_rounded, const Color(0xFFFF7A22)),
                selectedIcon: _navBadge(Icons.restaurant_rounded, const Color(0xFFFF7A22), selected: true),
                label: l.tabDiet,
              ),
              NavigationDestination(
                icon: _navBadge(Icons.fitness_center_rounded, const Color(0xFFEF5350)),
                selectedIcon: _navBadge(Icons.fitness_center_rounded, const Color(0xFFEF5350), selected: true),
                label: l.tabWorkout,
              ),
              NavigationDestination(
                icon: _navBadge(Icons.smart_toy_rounded, const Color(0xFFAB47BC)),
                selectedIcon: _navBadge(Icons.smart_toy_rounded, const Color(0xFFAB47BC), selected: true),
                label: l.tabAi,
              ),
            ],
          ),
        );
      },
    );
  }
}
