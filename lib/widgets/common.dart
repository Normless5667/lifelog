import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/targets.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../utils/l10n_ext.dart';

export '../theme/app_theme.dart';
export '../utils/l10n_ext.dart'
    show L10nBuildContext, L10nHelper, categoryVisual, courseIcon, foodEmoji;

/// 显示错误；如果是需要配置 AI 的错误，提供跳转按钮。
void showAiError(BuildContext context, Object e, {VoidCallback? onOpenSettings}) {
  final l = context.l10n;
  final needsConfig = e is AiException && e.needsConfig;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.danger(ctx)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(l.commonErrorTitle, style: AppTypography.cardTitle(ctx))),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(e.toString(), style: AppTypography.body(ctx)),
      ),
      actions: [
        if (needsConfig && onOpenSettings != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onOpenSettings();
            },
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: Text(l.commonGoSettings),
          ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonGotIt)),
      ],
    ),
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
}

Future<bool> confirm(BuildContext context, String message, {String? ok}) async {
  final l = context.l10n;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message, style: AppTypography.body(ctx, color: AppColors.textPrimary(ctx))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok ?? l.commonDelete)),
      ],
    ),
  );
  return r ?? false;
}

/// 克制的按压缩放反馈组件（自动遵循系统「减少动画」设置）
class ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const ScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (!reduceMotion) setState(() => _pressed = true);
      },
      onTapUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onTapCancel: () {
        if (_pressed) setState(() => _pressed = false);
      },
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: (_pressed && !reduceMotion) ? 0.975 : 1.0,
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// 统一表面卡片容器（支持 hero / card / subtle 三档阴影层级）
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool isHero;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.isHero = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (isHero ? AppRadius.bXxl : AppRadius.bXl);
    final bg = backgroundColor ?? AppColors.surface(context);
    final border = borderColor ??
        AppColors.border(context).withValues(alpha: AppColors.isDark(context) ? 0.75 : 0.85);

    final content = Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: border, width: 1),
        boxShadow: isHero ? AppShadows.hero(context) : AppShadows.card(context),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: padding ?? AppSpacing.cardPadding,
          child: child,
        ),
      ),
    );

    if (onTap == null) return content;
    return ScaleTap(onTap: onTap, borderRadius: radius, child: content);
  }
}

/// 热量进度环 + 三大营养素核心数据看板（Keep / Apple Health 风格）
class CalorieSummaryCard extends StatelessWidget {
  final DayTotals totals;
  final DailyTargets targets;
  final VoidCallback? onTap;

  const CalorieSummaryCard({
    super.key,
    required this.totals,
    required this.targets,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final remaining = targets.calories - totals.calories;
    final progress =
        targets.calories <= 0 ? 0.0 : (totals.calories / targets.calories).clamp(0.0, 1.0);
    final over = remaining < 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final primaryColor = AppColors.primary(context);
    final accentColor = AppColors.accent(context);
    final dangerColor = AppColors.danger(context);

    return SurfaceCard(
      isHero: true,
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左侧：品牌渐变热量圆环
              SizedBox(
                width: 116,
                height: 116,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 550),
                  curve: Curves.easeOutCubic,
                  builder: (context, animVal, child) {
                    return CustomPaint(
                      painter: _CalorieRingPainter(
                        progress: animVal,
                        trackColor: AppColors.surfaceSubtle(context),
                        startColor: over ? dangerColor : primaryColor,
                        endColor: over ? dangerColor : accentColor,
                      ),
                      child: child,
                    );
                  },
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.softBg(
                                context,
                                over ? dangerColor : accentColor,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              over
                                  ? Icons.warning_amber_rounded
                                  : Icons.local_fire_department_rounded,
                              color: over ? dangerColor : accentColor,
                              size: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              fmtNum(remaining.abs()),
                              style: AppTypography.displayMetric(
                                context,
                                color: over ? dangerColor : AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            over ? l.dietExceeded : l.dietRemaining,
                            style: AppTypography.caption(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              // 右侧：摄入/目标与三大营养素条
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l.dietConsumedTarget(
                              fmtNum(totals.calories),
                              fmtNum(targets.calories),
                            ),
                            style: AppTypography.subtitle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (targets.estimated) ...[
                      const SizedBox(height: 2),
                      Text(
                        l.dietEstimatedHint,
                        style: AppTypography.caption(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    MacroBar(
                      icon: Icons.egg_alt_rounded,
                      label: l.dietProtein,
                      value: totals.protein,
                      target: targets.protein,
                      color: AppColors.macroProtein(context),
                    ),
                    MacroBar(
                      icon: Icons.rice_bowl_rounded,
                      label: l.dietCarbs,
                      value: totals.carbs,
                      target: targets.carbs,
                      color: AppColors.macroCarbs(context),
                    ),
                    MacroBar(
                      icon: Icons.water_drop_rounded,
                      label: l.dietFat,
                      value: totals.fat,
                      target: targets.fat,
                      color: AppColors.macroFat(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // 底部：四格能量分解条（BMR / 运动消耗 / 今日摄入 / 热量盈余）
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle(context),
              borderRadius: AppRadius.bLg,
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _EnergyPill(
                    icon: Icons.bedtime_rounded,
                    color: AppColors.moduleSchedule(context),
                    label: l.dietBmr,
                    value: fmtNum(targets.bmr),
                    unit: 'kcal',
                  ),
                  _verticalDivider(context),
                  _EnergyPill(
                    icon: Icons.fitness_center_rounded,
                    color: AppColors.moduleWorkout(context),
                    label: l.dietTrainingBurn,
                    value: '+${fmtNum(targets.workoutBurn)}',
                    unit: 'kcal',
                  ),
                  _verticalDivider(context),
                  _EnergyPill(
                    icon: Icons.restaurant_rounded,
                    color: AppColors.moduleDiet(context),
                    label: l.dietTodayIntake,
                    value: fmtNum(totals.calories),
                    unit: 'kcal',
                  ),
                  _verticalDivider(context),
                  _EnergyPill(
                    icon: Icons.flag_rounded,
                    color: over ? dangerColor : AppColors.teal(context),
                    label: over ? l.dietExceeded : l.dietSurplus,
                    value: fmtNum(remaining.abs()),
                    unit: 'kcal',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.border(context),
    );
  }
}

class _CalorieRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  const _CalorieRingPainter({
    required this.progress,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 10.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.005) return;

    final sweepAngle = 2 * math.pi * p;
    const startAngle = -math.pi / 2;

    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [startColor, endColor, startColor],
        stops: const [0.0, 0.75, 1.0],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _CalorieRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor;
  }
}

class _EnergyPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;

  const _EnergyPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    style: AppTypography.caption(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: AppTypography.metricMedium(context, color: color)
                          .copyWith(fontSize: 13),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: AppTypography.caption(context).copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MacroBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double target;
  final Color color;

  const MacroBar({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: AppTypography.caption(
                      context,
                      color: AppColors.textPrimary(context),
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: fmtNum(value),
                      style: AppTypography.badge(
                        context,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    TextSpan(
                      text: ' / ${fmtNum(target)}g',
                      style: AppTypography.caption(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: AppRadius.bXs,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: p),
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, val, _) => LinearProgressIndicator(
                value: val,
                minHeight: 6,
                color: color,
                backgroundColor: AppColors.softBg(context, color, lightAlpha: 0.14, darkAlpha: 0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.icon, this.iconColor, this.trailing});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = iconColor != null
        ? AppColors.adaptForDark(context, iconColor!)
        : AppColors.primary(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, effectiveColor, lightAlpha: 0.12, darkAlpha: 0.18),
                borderRadius: AppRadius.bSm,
              ),
              child: Icon(icon, size: 16, color: effectiveColor),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTypography.sectionTitle(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyHint({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, primary, lightAlpha: 0.10, darkAlpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.softBorder(context, primary),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(6),
            child: ClipOval(
              child: Image.asset(
                'assets/icon/dafeiyu_mascot.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(icon, size: 56, color: primary.withValues(alpha: 0.85)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            text,
            style: AppTypography.body(context),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
