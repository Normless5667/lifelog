import 'package:flutter/material.dart';

import '../utils/route_speed_coloring.dart';
import 'common.dart';

/// 地图右下角五档配速分色图例：● 慢走  ● 慢跑  ● 正常  ● 快跑  ● 冲刺
class RouteSpeedLegend extends StatelessWidget {
  const RouteSpeedLegend({super.key});

  String _zoneLabel(BuildContext context, PaceZone zone) {
    final l = context.l10n;
    return switch (zone) {
      PaceZone.slowWalk => l.paceZoneWalk,
      PaceZone.jog => l.paceZoneJog,
      PaceZone.normal => l.paceZoneNormal,
      PaceZone.fast => l.paceZoneFast,
      PaceZone.sprint => l.paceZoneSprint,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('route_speed_legend'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface(context).withValues(alpha: 0.90),
        borderRadius: AppRadius.bPill,
        border: AppColors.isMidnight(context)
            ? null
            : Border.all(
                color: AppColors.border(context).withValues(alpha: 0.65),
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < PaceZone.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: PaceZone.values[i].color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              _zoneLabel(context, PaceZone.values[i]),
              style: AppTypography.caption(context).copyWith(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 地图上的轨迹着色模式切换胶囊：[单色轨迹 | 速度分色]
class RouteColorModeToggle extends StatelessWidget {
  final bool colorBySpeed;
  final ValueChanged<bool> onChanged;

  const RouteColorModeToggle({
    super.key,
    required this.colorBySpeed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final bg = AppColors.surface(context).withValues(alpha: 0.90);

    Widget chip({
      required Key key,
      required String label,
      required bool active,
      required VoidCallback onTap,
    }) {
      return InkWell(
        key: key,
        onTap: onTap,
        borderRadius: AppRadius.bPill,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? AppColors.softBg(context, primary, lightAlpha: 0.18, darkAlpha: 0.30)
                : Colors.transparent,
            borderRadius: AppRadius.bPill,
          ),
          child: Text(
            label,
            style: AppTypography.badge(
              context,
              color: active ? primary : AppColors.textSecondary(context),
            ).copyWith(fontSize: 10.5),
          ),
        ),
      );
    }

    return Material(
      key: const ValueKey('route_color_mode_toggle'),
      color: bg,
      borderRadius: AppRadius.bPill,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip(
              key: const ValueKey('route_mode_mono_btn'),
              label: l.routeColorModeMono,
              active: !colorBySpeed,
              onTap: () => onChanged(false),
            ),
            chip(
              key: const ValueKey('route_mode_speed_btn'),
              label: l.routeColorModeSpeed,
              active: colorBySpeed,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}
