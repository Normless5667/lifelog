import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// 关于页（v2.0）：展示大肥鱼 Q 版形象与说明
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = AppColors.primary(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.aboutTitle, style: AppTypography.pageTitle(context))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          SurfaceCard(
            isHero: true,
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.bXxl,
                    border: Border.all(color: AppColors.softBorder(context, primary)),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.bXl,
                    child: Image.asset(
                      'assets/icon/dafeiyu_mascot.png',
                      width: 128,
                      height: 128,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(l.appTitle, style: AppTypography.pageTitle(context)),
                const SizedBox(height: AppSpacing.xs),
                Text(l.aboutVersion, style: AppTypography.caption(context)),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md + 2,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, primary),
                    borderRadius: AppRadius.bPill,
                    border: Border.all(color: AppColors.softBorder(context, primary)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, size: 16, color: primary),
                      const SizedBox(width: AppSpacing.xs + 2),
                      Flexible(
                        child: Text(
                          l.aboutBadge,
                          style: AppTypography.subtitle(context, color: primary).copyWith(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l.aboutDesc,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
