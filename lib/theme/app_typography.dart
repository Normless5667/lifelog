import 'package:flutter/material.dart';
import 'app_colors.dart';

/// LifeLog v2.0 字体排版系统
/// - 核心数据（热量/步数/体重/倒计时/温度）使用高字重 + 等宽数字特性（tabularFigures）突出视觉焦点
/// - 依靠字重（w800 / w700 / w600 / w500 / w400）与明度对比建立清晰层级
abstract final class AppTypography {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// 超大核心指标数字（如热量环中心数字、大屏倒计时）
  static TextStyle displayMetric(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.1,
        fontFeatures: _tabular,
        color: color ?? AppColors.textPrimary(context),
      );

  /// 大号指标数字（如卡片主数值、温度、体重）
  static TextStyle metricLarge(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.15,
        fontFeatures: _tabular,
        color: color ?? AppColors.textPrimary(context),
      );

  /// 中号指标数字（如营养素克数、步数、分项卡路里）
  static TextStyle metricMedium(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.2,
        fontFeatures: _tabular,
        color: color ?? AppColors.textPrimary(context),
      );

  /// 页面顶栏标题
  static TextStyle pageTitle(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
        color: color ?? AppColors.textPrimary(context),
      );

  /// 分区标题（SectionTitle）
  static TextStyle sectionTitle(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.3,
        color: color ?? AppColors.textPrimary(context),
      );

  /// 卡片主标题
  static TextStyle cardTitle(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        height: 1.3,
        color: color ?? AppColors.textPrimary(context),
      );

  /// 列表/次级加粗标题
  static TextStyle subtitle(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: color ?? AppColors.textPrimary(context),
      );

  /// 常规正文
  static TextStyle body(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: color ?? AppColors.textSecondary(context),
      );

  /// 辅助说明文案
  static TextStyle bodySecondary(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: color ?? AppColors.textSecondary(context),
      );

  /// 胶囊/徽章/微小标签文字
  static TextStyle badge(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        height: 1.2,
        fontFeatures: _tabular,
        color: color ?? AppColors.textSecondary(context),
      );

  /// 底部说明/时间戳
  static TextStyle caption(BuildContext context, {Color? color}) => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        height: 1.25,
        fontFeatures: _tabular,
        color: color ?? AppColors.textTertiary(context),
      );
}
