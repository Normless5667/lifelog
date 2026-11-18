import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/targets.dart';
import '../utils/date_utils.dart';

/// 显示错误；如果是需要配置 AI 的错误，提供跳转按钮。
void showAiError(BuildContext context, Object e, {VoidCallback? onOpenSettings}) {
  final needsConfig = e is AiException && e.needsConfig;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent),
          SizedBox(width: 8),
          Text('出错了'),
        ],
      ),
      content: SingleChildScrollView(child: Text(e.toString())),
      actions: [
        if (needsConfig && onOpenSettings != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onOpenSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('去设置'),
          ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
      ],
    ),
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

Future<bool> confirm(BuildContext context, String message, {String ok = '删除'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// 根据食物名返回生动的 Emoji 图标
String foodEmoji(String name) {
  final n = name.toLowerCase();
  if (n.contains('鸡') || n.contains('chicken')) return '🍗';
  if (n.contains('牛') || n.contains('beef') || n.contains('steak')) return '🥩';
  if (n.contains('鱼') || n.contains('虾') || n.contains('海鲜')) return '🐟';
  if (n.contains('蛋') || n.contains('egg')) return '🍳';
  if (n.contains('奶') || n.contains('milk') || n.contains('豆浆')) return '🥛';
  if (n.contains('面') || n.contains('粉') || n.contains('noodle')) return '🍜';
  if (n.contains('饭') || n.contains('米') || n.contains('rice')) return '🍚';
  if (n.contains('面包') || n.contains('吐司') || n.contains('三明治')) return '🥪';
  if (n.contains('菜') || n.contains('沙拉') || n.contains('西兰花')) return '🥗';
  if (n.contains('果') || n.contains('香蕉') || n.contains('苹果')) return '🍎';
  if (n.contains('咖啡') || n.contains('美式') || n.contains('拿铁')) return '☕';
  return '🍱';
}

/// 根据课程名返回专属图标
IconData courseIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('database') || n.contains('数据')) return Icons.storage_rounded;
  if (n.contains('machine') || n.contains('ai') || n.contains('算法')) return Icons.psychology_rounded;
  if (n.contains('ux') || n.contains('design') || n.contains('设计')) return Icons.palette_rounded;
  if (n.contains('english') || n.contains('英语')) return Icons.translate_rounded;
  if (n.contains('math') || n.contains('数学')) return Icons.functions_rounded;
  return Icons.menu_book_rounded;
}

/// 根据训练部位返回专属颜色与图标
({IconData icon, Color color, String emoji}) categoryVisual(String cat) {
  switch (cat) {
    case '胸':
      return (icon: Icons.shield_rounded, color: const Color(0xFFEF5350), emoji: '🔥');
    case '背':
      return (icon: Icons.view_stream_rounded, color: const Color(0xFF42A5F5), emoji: '🪽');
    case '腿':
      return (icon: Icons.directions_run_rounded, color: const Color(0xFFAB47BC), emoji: '🦵');
    case '肩':
      return (icon: Icons.accessibility_new_rounded, color: const Color(0xFFFFA726), emoji: '💪');
    case '手臂':
      return (icon: Icons.fitness_center_rounded, color: const Color(0xFF26A69A), emoji: '🦾');
    case '核心':
      return (icon: Icons.grid_view_rounded, color: const Color(0xFF66BB6A), emoji: '⚡');
    case '有氧':
      return (icon: Icons.favorite_rounded, color: const Color(0xFFEC407A), emoji: '🏃');
    default:
      return (icon: Icons.sports_gymnastics_rounded, color: const Color(0xFF5C6BC0), emoji: '🏋️');
  }
}

/// 热量进度环 + 三大营养素视觉卡片（带彩色渐变背景与微图标）
class CalorieSummaryCard extends StatelessWidget {
  final DayTotals totals;
  final DailyTargets targets;
  final VoidCallback? onTap;

  const CalorieSummaryCard({super.key, required this.totals, required this.targets, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = targets.calories - totals.calories;
    final progress = targets.calories <= 0 ? 0.0 : (totals.calories / targets.calories).clamp(0.0, 1.0);
    final over = remaining < 0;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primaryContainer.withValues(alpha: 0.45),
                cs.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 112,
                    height: 112,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 11,
                          strokeCap: StrokeCap.round,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: over ? cs.error : cs.primary,
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                over ? Icons.warning_amber_rounded : Icons.local_fire_department_rounded,
                                color: over ? cs.error : Colors.orange,
                                size: 22,
                              ),
                              Text(
                                fmtNum(remaining.abs()),
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: over ? cs.error : null,
                                    ),
                              ),
                              Text(
                                over ? '超出 kcal' : '剩余额度',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.outline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bolt_rounded, size: 18, color: Colors.amber),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '摄入 ${fmtNum(totals.calories)} / 目标 ${fmtNum(targets.calories)} kcal',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        if (targets.estimated)
                          Text('（默认估算，点右上角填体重）',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline, fontSize: 11)),
                        const SizedBox(height: 8),
                        MacroBar(emoji: '🥩', label: '蛋白质', value: totals.protein, target: targets.protein, color: const Color(0xFFEF5350)),
                        MacroBar(emoji: '🍚', label: '碳水', value: totals.carbs, target: targets.carbs, color: const Color(0xFFFFA726)),
                        MacroBar(emoji: '🥑', label: '脂肪', value: totals.fat, target: targets.fat, color: const Color(0xFF42A5F5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  _EnergyPill(
                    icon: Icons.bedtime_rounded,
                    color: const Color(0xFF42A5F5),
                    label: '基础代谢',
                    value: '${fmtNum(targets.bmr)} kcal',
                  ),
                  _EnergyPill(
                    icon: Icons.fitness_center_rounded,
                    color: const Color(0xFFEF5350),
                    label: '训练消耗',
                    value: '+${fmtNum(targets.workoutBurn)} kcal',
                  ),
                  _EnergyPill(
                    icon: Icons.restaurant_rounded,
                    color: const Color(0xFFFFA726),
                    label: '今日摄入',
                    value: '${fmtNum(totals.calories)} kcal',
                  ),
                  _EnergyPill(
                    icon: Icons.flag_rounded,
                    color: over ? cs.error : const Color(0xFF26A69A),
                    label: over ? '已超出' : '剩余额度',
                    value: '${fmtNum(remaining.abs())} kcal',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnergyPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _EnergyPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class MacroBar extends StatelessWidget {
  final String emoji;
  final String label;
  final double value;
  final double target;
  final Color color;

  const MacroBar({
    super.key,
    required this.emoji,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$emoji $label', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text('${fmtNum(value)} / ${fmtNum(target)}g', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 7,
              color: color,
              backgroundColor: color.withValues(alpha: 0.16),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (iconColor ?? cs.primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor ?? cs.primary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(6),
            child: ClipOval(
              child: Image.asset(
                'assets/icon/dafeiyu_mascot.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(icon, size: 72, color: cs.primary.withValues(alpha: 0.85)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.outline, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
