import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/reminder_service.dart';
import '../../services/running_tracker.dart';
import '../../widgets/common.dart';

/// 检查并引导跑步所需的精确位置 + 通知 + Android 11+ 后台定位权限。
/// 返回 true 表示已具备基础定位权限可以开始跑步。
Future<bool> ensureRunningPermissions(BuildContext context) async {
  final l = context.l10n;

  // 1) 请求通知权限（确保前台服务「正在记录跑步」常驻通知可见）
  await ReminderService.requestPermission();

  // 2) 检查定位服务与前台位置权限
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    if (!context.mounted) return false;
    final retry = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => _PermissionGuideSheet(
        needsForeground: true,
        needsBackground: true,
        onRequestForeground: () async {
          final p = await Geolocator.requestPermission();
          if (p == LocationPermission.whileInUse || p == LocationPermission.always) {
            if (ctx.mounted) Navigator.pop(ctx, true);
          } else {
            await RunningNativeService.openAppSettings();
          }
        },
        onOpenSettings: () async {
          await RunningNativeService.openAppSettings();
        },
        onContinueFg: () => Navigator.pop(ctx, false),
      ),
    );
    if (retry == true) {
      perm = await Geolocator.checkPermission();
    }
    if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) {
      if (context.mounted) toast(context, l.runPermDeniedToast);
      return false;
    }
  }

  // 3) Android 11+ 单独引导后台定位权限（不能只弹一次系统对话框）
  final nativeStatus = await RunningNativeService.checkLocationPermissions();
  if (nativeStatus.sdkInt >= 30 && !nativeStatus.background) {
    if (!context.mounted) return true;
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => _PermissionGuideSheet(
        needsForeground: false,
        needsBackground: true,
        onRequestForeground: () async {},
        onOpenSettings: () async {
          await RunningNativeService.openAppSettings();
        },
        onContinueFg: () => Navigator.pop(ctx, true),
      ),
    );
    return proceed ?? true;
  }

  return true;
}

class _PermissionGuideSheet extends StatelessWidget {
  final bool needsForeground;
  final bool needsBackground;
  final Future<void> Function() onRequestForeground;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onContinueFg;

  const _PermissionGuideSheet({
    required this.needsForeground,
    required this.needsBackground,
    required this.onRequestForeground,
    required this.onOpenSettings,
    required this.onContinueFg,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);
    final warning = AppColors.warning(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, primary),
                  borderRadius: AppRadius.bMd,
                ),
                child: Icon(Icons.my_location_rounded, color: primary, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(l.runPermTitle, style: AppTypography.sectionTitle(context)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l.runPermDesc, style: AppTypography.body(context)),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: AppSpacing.cardCompactPadding,
            decoration: BoxDecoration(
              color: AppColors.softBg(context, warning, lightAlpha: 0.10, darkAlpha: 0.18),
              borderRadius: AppRadius.bMd,
              border: Border.all(color: AppColors.softBorder(context, warning)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.runPermStep1, style: AppTypography.body(context)),
                const SizedBox(height: AppSpacing.xs),
                Text(l.runPermStep2, style: AppTypography.body(context)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (needsForeground)
            FilledButton.icon(
              onPressed: onRequestForeground,
              icon: const Icon(Icons.location_on_rounded, size: 18),
              label: Text(l.runPermRequestBtn),
            ),
          if (needsBackground) ...[
            if (needsForeground) const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: Text(l.runPermOpenSettingsBtn),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onContinueFg,
            child: Text(needsForeground ? l.commonCancel : l.runPermContinueFgBtn),
          ),
        ],
      ),
    );
  }
}
