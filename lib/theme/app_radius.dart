import 'package:flutter/widgets.dart';

/// 统一圆角体系（卡片 / 按钮 / 输入框 / 图标容器 / 胶囊各一档）
abstract final class AppRadius {
  /// 微小标签或进度条 (6dp)
  static const double xs = 6.0;

  /// 小型徽章 / 内部块 (10dp)
  static const double sm = 10.0;

  /// 输入框 / 图标方块容器 (12dp)
  static const double md = 12.0;

  /// 按钮 / 次级卡片 / 快捷入口 (16dp)
  static const double lg = 16.0;

  /// 主卡片 / 底部弹窗 (20dp)
  static const double xl = 20.0;

  /// 大型看板卡片 (24dp)
  static const double xxl = 24.0;

  /// 胶囊形 (999dp)
  static const double pill = 999.0;

  static final BorderRadius bXs = BorderRadius.circular(xs);
  static final BorderRadius bSm = BorderRadius.circular(sm);
  static final BorderRadius bMd = BorderRadius.circular(md);
  static final BorderRadius bLg = BorderRadius.circular(lg);
  static final BorderRadius bXl = BorderRadius.circular(xl);
  static final BorderRadius bXxl = BorderRadius.circular(xxl);
  static final BorderRadius bPill = BorderRadius.circular(pill);
}
