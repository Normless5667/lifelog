import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';

export 'app_colors.dart';
export 'app_radius.dart';
export 'app_shadows.dart';
export 'app_spacing.dart';
export 'app_typography.dart';

/// Material 3 克制动效规范 Token（所有动效严格 <= 400ms，自动遵循系统「减少动画」）
abstract final class AppMotion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration short4 = Duration(milliseconds: 200);
  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration pageTransition = Duration(milliseconds: 260);
  static const Duration medium2 = Duration(milliseconds: 300);

  static const Curve pressCurve = Curves.easeOut;
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  /// 页面/Tab 切换轻微水平位移幅度（约 16dp）
  static const double subtleSlidePx = 16.0;
}

/// Material 3 克制页面转场：淡入淡出 + 16dp 轻微水平位移，减少动画模式下瞬间切换
class M3SubtlePageTransitionsBuilder extends PageTransitionsBuilder {
  const M3SubtlePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.standardCurve,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, c) {
        final t = curved.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(AppMotion.subtleSlidePx * (1.0 - t), 0),
            child: c,
          ),
        );
      },
    );
  }
}

/// 组装浅色与深色 ThemeData
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final teal = isDark ? AppColors.tealDark : AppColors.tealLight;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceSubtle = isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryLight,
      brightness: brightness,
      primary: primary,
      secondary: accent,
      tertiary: teal,
      surface: surface,
      error: isDark ? AppColors.dangerDark : AppColors.dangerLight,
    );

    final cs = baseScheme.copyWith(
      surface: surface,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceSubtle,
      surfaceContainerHigh: surfaceSubtle,
      surfaceContainerHighest: border,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: textSecondary,
      outlineVariant: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: M3SubtlePageTransitionsBuilder(),
          TargetPlatform.iOS: M3SubtlePageTransitionsBuilder(),
          TargetPlatform.macOS: M3SubtlePageTransitionsBuilder(),
          TargetPlatform.windows: M3SubtlePageTransitionsBuilder(),
          TargetPlatform.linux: M3SubtlePageTransitionsBuilder(),
          TargetPlatform.fuchsia: M3SubtlePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        color: surface,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.bXl,
          side: BorderSide(color: border.withValues(alpha: isDark ? 0.75 : 0.85), width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF131A24).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? textPrimary : textSecondary,
            letterSpacing: -0.1,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.bLg),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.bLg),
          side: BorderSide(color: border),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.bMd,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.bMd,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.bMd,
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        hintStyle: TextStyle(
          fontSize: 13.5,
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceSubtle,
        selectedColor: primary.withValues(alpha: isDark ? 0.22 : 0.14),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: textPrimary),
      ),
      dividerTheme: DividerThemeData(
        color: border.withValues(alpha: isDark ? 0.6 : 0.8),
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.bXl),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
      ),
    );
  }
}
