import 'package:flutter/widgets.dart';

/// 8pt 基准空间与间距系统（含 4pt 微调档）
abstract final class AppSpacing {
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  /// 页面底部留白（避开底部导航与悬浮按钮）
  static const double pageBottom = 104.0;

  /// 标准页面内边距
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(lg, sm, lg, pageBottom);

  /// 标准卡片内边距
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  /// 紧凑卡片内边距
  static const EdgeInsets cardCompactPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}
