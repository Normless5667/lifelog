import 'dart:ui';

import 'package:flutter/material.dart';

/// Gemini 风格「深夜黑」高级皮肤核心色板（v3.1.2）
abstract final class GeminiDarkColors {
  static const Color bgTop = Color(0xFF000000);
  static const Color bgBottom = Color(0xFF0A0E27);
  static const Color surface = Color(0xFF15161A); // 无边框浮层卡片
  static const Color surfaceAlt = Color(0xFF1E1F24); // 深灰胶囊输入框 / 次级表面
  static const Color textPrimary = Color(0xFFE8EAED);
  static const Color textSecondary = Color(0xFF9AA0A6);
  static const Color textTertiary = Color(0xFF6E7580);

  // Gemini 四色强调系统
  static const Color accent = Color(0xFF4285F4); // 主蓝
  static const Color red = Color(0xFFEA4335);
  static const Color yellow = Color(0xFFFBBC04);
  static const Color green = Color(0xFF34A853);
}

/// 挂载到 ThemeData 的皮肤扩展（用于区分默认浅色 / 常规深色 / Gemini 深夜黑）
class AppSkinExtension extends ThemeExtension<AppSkinExtension> {
  final bool isMidnight;
  final Color bgTop;
  final Color bgBottom;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final double cardRadius;
  final double heroCardRadius;
  final bool borderlessCards;

  const AppSkinExtension({
    required this.isMidnight,
    required this.bgTop,
    required this.bgBottom,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.cardRadius,
    required this.heroCardRadius,
    required this.borderlessCards,
  });

  static const AppSkinExtension lightStandard = AppSkinExtension(
    isMidnight: false,
    bgTop: Color(0xFFF4F7FA),
    bgBottom: Color(0xFFF4F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF2F7),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF94A3B8),
    accent: Color(0xFF1E4D7B),
    cardRadius: 20,
    heroCardRadius: 24,
    borderlessCards: false,
  );

  static const AppSkinExtension darkStandard = AppSkinExtension(
    isMidnight: false,
    bgTop: Color(0xFF0E131B),
    bgBottom: Color(0xFF0E131B),
    surface: Color(0xFF171F2C),
    surfaceAlt: Color(0xFF202A3B),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF64748B),
    accent: Color(0xFF63A8E8),
    cardRadius: 20,
    heroCardRadius: 24,
    borderlessCards: false,
  );

  /// Gemini 深夜黑：纯黑到深蓝渐变、无边框大圆角 24~28dp、极轻微亮度差分层
  static const AppSkinExtension midnightPremium = AppSkinExtension(
    isMidnight: true,
    bgTop: GeminiDarkColors.bgTop,
    bgBottom: GeminiDarkColors.bgBottom,
    surface: GeminiDarkColors.surface,
    surfaceAlt: GeminiDarkColors.surfaceAlt,
    textPrimary: GeminiDarkColors.textPrimary,
    textSecondary: GeminiDarkColors.textSecondary,
    textTertiary: GeminiDarkColors.textTertiary,
    accent: GeminiDarkColors.accent,
    cardRadius: 24,
    heroCardRadius: 28,
    borderlessCards: true,
  );

  static AppSkinExtension of(BuildContext context) {
    final ext = Theme.of(context).extension<AppSkinExtension>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? darkStandard : lightStandard;
  }

  static bool isMidnightOf(BuildContext context) => of(context).isMidnight;

  @override
  AppSkinExtension copyWith({
    bool? isMidnight,
    Color? bgTop,
    Color? bgBottom,
    Color? surface,
    Color? surfaceAlt,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    double? cardRadius,
    double? heroCardRadius,
    bool? borderlessCards,
  }) =>
      AppSkinExtension(
        isMidnight: isMidnight ?? this.isMidnight,
        bgTop: bgTop ?? this.bgTop,
        bgBottom: bgBottom ?? this.bgBottom,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        accent: accent ?? this.accent,
        cardRadius: cardRadius ?? this.cardRadius,
        heroCardRadius: heroCardRadius ?? this.heroCardRadius,
        borderlessCards: borderlessCards ?? this.borderlessCards,
      );

  @override
  AppSkinExtension lerp(covariant ThemeExtension<AppSkinExtension>? other, double t) {
    if (other is! AppSkinExtension) return this;
    return AppSkinExtension(
      isMidnight: t < 0.5 ? isMidnight : other.isMidnight,
      bgTop: Color.lerp(bgTop, other.bgTop, t) ?? bgTop,
      bgBottom: Color.lerp(bgBottom, other.bgBottom, t) ?? bgBottom,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t) ?? surfaceAlt,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t) ?? cardRadius,
      heroCardRadius: lerpDouble(heroCardRadius, other.heroCardRadius, t) ?? heroCardRadius,
      borderlessCards: t < 0.5 ? borderlessCards : other.borderlessCards,
    );
  }
}

/// 固定在应用根部的深夜黑纯黑→深蓝渐变背景层：
/// 使用 RepaintBoundary 隔离光栅化，全应用页面透明浮在其上，滚动零掉帧。
class MidnightBackdropLayer extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const MidnightBackdropLayer({
    super.key,
    required this.child,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: DecoratedBox(
            key: ValueKey('gemini_midnight_gradient_bg'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [GeminiDarkColors.bgTop, GeminiDarkColors.bgBottom],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
