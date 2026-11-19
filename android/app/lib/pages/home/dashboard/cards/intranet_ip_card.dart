import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class IntranetIpCard extends ConsumerWidget {
  const IntranetIpCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkInfoProvider);
    final snapshot = network.asData?.value;
    final loading = network.isLoading;
    final mode = ref.watch(workModeProvider);
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    final localIp = snapshot?.localIpv4 ?? '';
    final address = localIp.isEmpty ? null : localIp;
    final placeholder = loading
        ? context.l10n.intranetReading
        : context.l10n.intranetNoActiveNetwork;
    return DashboardCard(
      semanticLabel: context.l10n.intranetIpTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: context.l10n.intranetIpTitle,
            trailing: [
              DashboardIconButton(
                glyph: AppGlyphs.copy,
                tooltip: context.l10n.intranetCopyAddress,
                onPressed: address == null
                    ? null
                    : () => _copy(context, address),
              ),
              if (onDetail != null)
                DashboardIconButton(
                  glyph: AppGlyphs.chevronForward,
                  tooltip: context.l10n.dashboardDetailTooltip,
                  onPressed: onDetail,
                ),
            ],
          ),
          SizedBox(height: 12 * scale),
          Text(
            address ?? placeholder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.figure(
              context,
              AppTextStyle.title1,
              color: address == null
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurface,
            ).copyWith(letterSpacing: 0),
          ),
          SizedBox(height: 12 * scale),
          DashboardBlock(
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 9 * scale,
            ),
            child: Row(
              spacing: 10,
              children: [
                GlyphIcon(
                  localIp.isEmpty ? AppGlyphs.wifiOff : AppGlyphs.wifi,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 1,
                    children: [
                      Text(
                        context.l10n.intranetLanAccess,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardText.rowTitle(context),
                      ),
                      Text(
                        _lanHint(mode, localIp.isEmpty, context.l10n),
                        maxLines: 2,
                        style: DashboardText.label(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (snapshot case final info? when info.interfaceName.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8 * scale),
              child: Text(
                '${info.interfaceName}'
                '${(info.gateway ?? '').isEmpty ? '' : context.l10n.intranetGatewaySuffix(info.gateway!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(context),
              ),
            ),
        ],
      ),
    );
  }

  /// The tunnel modes bind DNS to loopback, so the address is informational only.
  static String _lanHint(
    AppWorkMode mode,
    bool noNetwork,
    AppL10n l10n,
  ) {
    if (noNetwork) return l10n.intranetConnectHint;
    return l10n.intranetModeNotListening(mode.title(l10n));
  }

  static Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppSnack(
      context,
      context.l10n.commonCopied(text),
      duration: const Duration(milliseconds: 1600),
    );
  }
}
