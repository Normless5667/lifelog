import 'package:flutter/material.dart';

/// LifeLog v2.0 统一色彩系统
/// - 浅色模式：清爽高对比，深海蓝主色 + 活力珊瑚橙强调色
/// - 深色模式：大幅降低模块色饱和度（融入深邃蓝灰基底），避免刺眼实心色块
abstract final class AppColors {
  // ── 品牌核心色 ─────────────────────────────────────────────
  static const Color primaryLight = Color(0xFF1E4D7B);
  static const Color primaryDark = Color(0xFF63A8E8);

  static const Color accentLight = Color(0xFFFF6B2C);
  static const Color accentDark = Color(0xFFFF8F5E);

  static const Color tealLight = Color(0xFF14968B);
  static const Color tealDark = Color(0xFF4AC2B7);

  // ── 背景与表面层级 ─────────────────────────────────────────
  static const Color bgLight = Color(0xFFF4F7FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSubtleLight = Color(0xFFEDF2F7);
  static const Color borderLight = Color(0xFFE2E8F0);

  static const Color bgDark = Color(0xFF0E131B);
  static const Color surfaceDark = Color(0xFF171F2C);
  static const Color surfaceSubtleDark = Color(0xFF202A3B);
  static const Color borderDark = Color(0xFF293548);

  // ── 文本层级 ───────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textTertiaryLight = Color(0xFF94A3B8);

  static const Color textPrimaryDark = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark = Color(0xFF64748B);

  // ── 五大模块语义色（浅色鲜明 / 深色降饱和） ───────────────────
  static const Color moduleTodayLight = Color(0xFF1E4D7B);
  static const Color moduleTodayDark = Color(0xFF63A8E8);

  static const Color moduleScheduleLight = Color(0xFF0284C7);
  static const Color moduleScheduleDark = Color(0xFF58B4F5);

  static const Color moduleDietLight = Color(0xFFF97316);
  static const Color moduleDietDark = Color(0xFFF6995C);

  static const Color moduleWorkoutLight = Color(0xFFE11D48);
  static const Color moduleWorkoutDark = Color(0xFFF0718F);

  static const Color moduleBodyLight = Color(0xFF0D9488);
  static const Color moduleBodyDark = Color(0xFF4AC2B7);

  static const Color moduleAiLight = Color(0xFF7C3AED);
  static const Color moduleAiDark = Color(0xFFA78BFA);

  // ── 三大营养素与能量色 ─────────────────────────────────────
  static const Color macroProteinLight = Color(0xFFE11D48);
  static const Color macroProteinDark = Color(0xFFF0718F);

  static const Color macroCarbsLight = Color(0xFFEA580C);
  static const Color macroCarbsDark = Color(0xFFFBBF24);

  static const Color macroFatLight = Color(0xFF0284C7);
  static const Color macroFatDark = Color(0xFF58B4F5);

  // ── 状态语义色 ─────────────────────────────────────────────
  static const Color successLight = Color(0xFF10B981);
  static const Color successDark = Color(0xFF34D399);

  static const Color warningLight = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFFBBF24);

  static const Color dangerLight = Color(0xFFEF4444);
  static const Color dangerDark = Color(0xFFF87171);

  static const Color infoLight = Color(0xFF3B82F6);
  static const Color infoDark = Color(0xFF60A5FA);

  // ── 上下文感知读取器 ───────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color primary(BuildContext context) =>
      isDark(context) ? primaryDark : primaryLight;

  static Color accent(BuildContext context) =>
      isDark(context) ? accentDark : accentLight;

  static Color teal(BuildContext context) =>
      isDark(context) ? tealDark : tealLight;

  static Color bg(BuildContext context) =>
      isDark(context) ? bgDark : bgLight;

  static Color surface(BuildContext context) =>
      isDark(context) ? surfaceDark : surfaceLight;

  static Color surfaceSubtle(BuildContext context) =>
      isDark(context) ? surfaceSubtleDark : surfaceSubtleLight;

  static Color border(BuildContext context) =>
      isDark(context) ? borderDark : borderLight;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? textPrimaryDark : textPrimaryLight;

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? textSecondaryDark : textSecondaryLight;

  static Color textTertiary(BuildContext context) =>
      isDark(context) ? textTertiaryDark : textTertiaryLight;

  // 模块色获取器
  static Color moduleToday(BuildContext context) =>
      isDark(context) ? moduleTodayDark : moduleTodayLight;

  static Color moduleSchedule(BuildContext context) =>
      isDark(context) ? moduleScheduleDark : moduleScheduleLight;

  static Color moduleDiet(BuildContext context) =>
      isDark(context) ? moduleDietDark : moduleDietLight;

  static Color moduleWorkout(BuildContext context) =>
      isDark(context) ? moduleWorkoutDark : moduleWorkoutLight;

  static Color moduleBody(BuildContext context) =>
      isDark(context) ? moduleBodyDark : moduleBodyLight;

  static Color moduleAi(BuildContext context) =>
      isDark(context) ? moduleAiDark : moduleAiLight;

  // 营养素色获取器
  static Color macroProtein(BuildContext context) =>
      isDark(context) ? macroProteinDark : macroProteinLight;

  static Color macroCarbs(BuildContext context) =>
      isDark(context) ? macroCarbsDark : macroCarbsLight;

  static Color macroFat(BuildContext context) =>
      isDark(context) ? macroFatDark : macroFatLight;

  // 状态色获取器
  static Color success(BuildContext context) =>
      isDark(context) ? successDark : successLight;

  static Color warning(BuildContext context) =>
      isDark(context) ? warningDark : warningLight;

  static Color danger(BuildContext context) =>
      isDark(context) ? dangerDark : dangerLight;

  static Color info(BuildContext context) =>
      isDark(context) ? infoDark : infoLight;

  /// 将任意颜色在深色模式下自动向背景色柔和过渡（适合课程自定义色等动态色值）
  static Color adaptForDark(BuildContext context, Color rawColor) {
    if (!isDark(context)) return rawColor;
    final hsl = HSLColor.fromColor(rawColor);
    return hsl
        .withSaturation((hsl.saturation * 0.72).clamp(0.25, 0.75))
        .withLightness(hsl.lightness.clamp(0.58, 0.78))
        .toColor();
  }

  /// 模块/图标柔和低透明度背景（深色模式不刺眼，浅色模式清爽通透）
  static Color softBg(
    BuildContext context,
    Color baseColor, {
    double lightAlpha = 0.10,
    double darkAlpha = 0.15,
  }) {
    final adapted = adaptForDark(context, baseColor);
    return adapted.withValues(alpha: isDark(context) ? darkAlpha : lightAlpha);
  }

  /// 模块/胶囊柔和描边色
  static Color softBorder(
    BuildContext context,
    Color baseColor, {
    double lightAlpha = 0.22,
    double darkAlpha = 0.28,
  }) {
    final adapted = adaptForDark(context, baseColor);
    return adapted.withValues(alpha: isDark(context) ? darkAlpha : lightAlpha);
  }
}
