import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 底部导航栏单项数据
class M3NavDestination {
  final IconData icon;
  final String label;
  final Color color;

  const M3NavDestination({
    required this.icon,
    required this.label,
    required this.color,
  });
}

/// Material 3 克制滑动药丸指示器底部导航栏
/// - 选中图标平滑缩放（24 -> 28）
/// - 图标与文案颜色平滑过渡
/// - 64x32 StadiumBorder 药丸指示器横向滑动（250ms, Curves.easeInOutCubicEmphasized）
/// - 自动遵循 MediaQuery.disableAnimationsOf(context)
class M3SlidingNavBar extends StatelessWidget {
  static const double pillWidth = 64;
  static const double pillHeight = 32;
  static const double barHeight = 68;
  static const double unselectedIconSize = 24;
  static const double selectedIconSize = 28;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<M3NavDestination> destinations;

  const M3SlidingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppMotion.medium1;
    final curve = AppMotion.emphasizedCurve;
    final isDark = AppColors.isDark(context);
    final navTheme = Theme.of(context).navigationBarTheme;
    final bgColor = navTheme.backgroundColor ?? AppColors.surface(context);
    final activeItem = destinations[selectedIndex.clamp(0, destinations.length - 1)];
    final pillColor = AppColors.softBg(
      context,
      activeItem.color,
      lightAlpha: 0.14,
      darkAlpha: 0.22,
    );
    final pillBorderColor = AppColors.softBorder(
      context,
      activeItem.color,
      lightAlpha: 0.24,
      darkAlpha: 0.34,
    );
    final unselectedColor = AppColors.textSecondary(context);
    final selectedTextColor = AppColors.textPrimary(context);

    return Material(
      color: bgColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.border(context).withValues(alpha: isDark ? 0.65 : 0.85),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: barHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = destinations.length;
                final slotWidth = count > 0 ? constraints.maxWidth / count : constraints.maxWidth;
                final clampedIndex = selectedIndex.clamp(0, count - 1);
                final pillLeft = clampedIndex * slotWidth + (slotWidth - pillWidth) / 2;

                return Stack(
                  children: [
                    AnimatedPositioned(
                      key: const ValueKey('m3_nav_sliding_pill'),
                      duration: duration,
                      curve: curve,
                      left: pillLeft,
                      top: 8,
                      width: pillWidth,
                      height: pillHeight,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: curve,
                        decoration: ShapeDecoration(
                          color: pillColor,
                          shape: StadiumBorder(
                            side: BorderSide(color: pillBorderColor, width: 1),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(count, (i) {
                        final item = destinations[i];
                        final selected = i == clampedIndex;
                        final targetIconColor = selected ? item.color : unselectedColor;
                        final targetIconSize = selected ? selectedIconSize : unselectedIconSize;

                        return Expanded(
                          child: Semantics(
                            button: true,
                            selected: selected,
                            label: item.label,
                            child: InkWell(
                              onTap: () => onDestinationSelected(i),
                              borderRadius: AppRadius.bLg,
                              splashColor: item.color.withValues(alpha: 0.12),
                              highlightColor: Colors.transparent,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: pillHeight,
                                    child: Center(
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween<double>(end: targetIconSize),
                                        duration: duration,
                                        curve: curve,
                                        builder: (context, iconSize, _) {
                                          return TweenAnimationBuilder<Color?>(
                                            tween: ColorTween(end: targetIconColor),
                                            duration: duration,
                                            curve: curve,
                                            builder: (context, iconColor, _) {
                                              return Icon(
                                                item.icon,
                                                size: iconSize,
                                                color: iconColor ?? targetIconColor,
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AnimatedDefaultTextStyle(
                                    duration: duration,
                                    curve: curve,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      color: selected ? selectedTextColor : unselectedColor,
                                      letterSpacing: -0.1,
                                    ),
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
