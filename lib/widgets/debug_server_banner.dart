import 'package:flutter/material.dart';

import '../debug/debug_server.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// 调试服务运行期间常驻 App 顶部的红色警示条：
/// - 只要 Wi-Fi 调试服务处于开启状态，无论切换到哪个页面都始终可见，防止用完忘关
/// - 点击整条即可立即关闭调试服务
class DebugServerBannerHost extends StatelessWidget {
  final Widget child;
  final DebugServer? server;

  const DebugServerBannerHost({
    super.key,
    required this.child,
    this.server,
  });

  @override
  Widget build(BuildContext context) {
    final srv = server ?? DebugServer.instance;
    return ListenableBuilder(
      listenable: srv,
      builder: (context, _) {
        if (!srv.isRunning) return child;
        final l = AppLocalizations.of(context);
        final address = '${srv.ipAddress}:${srv.port}';
        final text = l?.debugServerBannerText(address) ?? 'DEBUG ON · $address';

        return Column(
          children: [
            Material(
              key: const ValueKey('debug_server_top_banner'),
              color: AppColors.danger(context),
              child: SafeArea(
                bottom: false,
                child: InkWell(
                  onTap: () => srv.stop(reason: 'banner_tap'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bug_report_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.badge(
                              context,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
