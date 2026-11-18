import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 按视觉层级递减的阴影系统（深色模式下弱化投影、依靠表面色差与微描边建立层级）
abstract final class AppShadows {
  /// 一级主看板卡片（如今日热量环、核心焦点卡片）
  static List<BoxShadow> hero(BuildContext context) {
    if (AppColors.isDark(context)) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.06),
        blurRadius: 20,
        spreadRadius: 0,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// 二级常规卡片（天气、校车、课表、运动、身体）
  static List<BoxShadow> card(BuildContext context) {
    if (AppColors.isDark(context)) {
      return const [];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ];
  }

  /// 三级轻量组件（快捷入口、小胶囊、悬浮操作）
  static List<BoxShadow> subtle(BuildContext context) {
    if (AppColors.isDark(context)) {
      return const [];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.025),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }
}
