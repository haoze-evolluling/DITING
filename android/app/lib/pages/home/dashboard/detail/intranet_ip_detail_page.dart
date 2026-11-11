import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Intranet IP detail: the card fits one address and a one-line hint. This page lists the whole
/// network snapshot — interface, IPv4/IPv6, gateway, DNS servers, VPN and private-DNS state — plus
/// the exact DNS address other devices should point at, so the user never has to guess the port.
class IntranetIpDetailPage extends ConsumerWidget {
  const IntranetIpDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkInfoProvider);
    final info = network.asData?.value;
    final mode = ref.watch(workModeProvider);
    final serverStatus = ref.watch(serverStatusProvider);
    final port = ref.watch(serverPortProvider);
    final colorScheme = context.colorScheme;
    final localIp = info?.localIpv4 ?? '';
    final listening =
        mode == AppWorkMode.server && serverStatus == ServerStatus.running;
    final dnsAddress = localIp.isEmpty
        ? null
        : listening
        ? '$localIp:$port'
        : localIp;
    final dnsServers = info?.dnsServers ?? const <String>[];
    return DashboardDetailScaffold(
      title: context.l10n.intranetDetailTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.intranetRefresh,
          onPressed: () => ref.invalidate(networkInfoProvider),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      children: [
        DashboardDetailHero(
          glyph: AppGlyphs.wifi,
          label: context.l10n.intranetLocalAddress,
          value: dnsAddress ?? (network.isLoading ? context.l10n.intranetReading : context.l10n.intranetNoActiveNetwork),
          tabular: dnsAddress != null,
          chipLabel: listening ? context.l10n.intranetUsableAsDns : context.l10n.intranetLocalOnly,
          chipColor: listening
              ? colorScheme.success
              : colorScheme.onSurfaceVariant,
          hint: listening
              ? context.l10n.intranetSameSubnetHint
              : localIp.isEmpty
              ? context.l10n.intranetConnectHintSentence
              : context.l10n.intranetModeNotListeningSentence(mode.title(context.l10n)),
        ),
        if (dnsAddress != null)
          _CopyCard(address: dnsAddress, withPort: listening),
        DashboardDetailCard(
          glyph: AppGlyphs.connections,
          title: context.l10n.intranetNetworkOverview,
          child: DashboardStatGrid(
            stats: [
              StatItem(label: 'IPv4', value: localIp.isEmpty ? '—' : localIp),
              StatItem(
                label: 'VPN',
                value: info?.vpnActive == true ? context.l10n.commonEnabled : context.l10n.commonDisabled,
                color: info?.vpnActive == true ? colorScheme.primary : null,
              ),
              StatItem(label: context.l10n.intranetDnsServers, value: '${dnsServers.length}'),
              StatItem(
                label: context.l10n.statusListenPort,
                value: listening ? '$port' : context.l10n.statusNotListening,
                color: listening ? colorScheme.primary : null,
              ),
            ],
          ),
        ),
        DashboardDetailCard(
          glyph: AppGlyphs.wifi,
          title: context.l10n.intranetInterfaces,
          footer: info == null || info.interfaceName.isEmpty
              ? context.l10n.intranetNoInterface
              : null,
          child: DashboardDetailRows(
            rows: [
              DashboardDetailRow(
                label: context.l10n.intranetAdapter,
                value: networkInterfaceLabel(info ?? _emptyInfo),
                tabular: true,
              ),
              DashboardDetailRow(
                label: 'IPv4',
                value: localIp.isEmpty ? '—' : localIp,
                tabular: true,
              ),
              DashboardDetailRow(
                label: 'IPv6',
                value: info?.localIpv6?.isNotEmpty == true
                    ? info!.localIpv6!
                    : '—',
                tabular: true,
              ),
              DashboardDetailRow(
                label: context.l10n.intranetGateway,
                value: info?.gateway?.isNotEmpty == true ? info!.gateway! : '—',
                tabular: true,
              ),
            ],
          ),
        ),
        DashboardDetailCard(
          glyph: AppGlyphs.dns,
          title: 'DNS',
          footer: info != null && info.privateDns != 'off'
              ? context.l10n.intranetPrivateDnsOn('${info.privateDns}')
              : context.l10n.intranetPrivateDnsOff,
          child: dnsServers.isEmpty
              ? Row(
                  spacing: 10,
                  children: [
                    GlyphIcon(
                      AppGlyphs.info,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    Expanded(
                      child: Text(
                        context.l10n.intranetNoDnsServer,
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                )
              : DashboardDetailRows(
                  rows: [
                    // Numbered: a column of rows all labelled "DNS" left no way to tell
                    // which server was the primary one.
                    for (final (index, server) in dnsServers.indexed)
                      DashboardDetailRow(
                        label: index == 0
                            ? context.l10n.intranetPrimaryDns
                            : context.l10n.intranetSecondaryDns(index),
                        value: server,
                        tabular: true,
                      ),
                    DashboardDetailRow(
                      label: context.l10n.intranetPrivateDns,
                      value: info?.privateDns ?? '—',
                    ),
                  ],
                ),
        ),
        DashboardDetailNote(text: context.l10n.intranetPortFooter),
      ],
    );
  }

  static const _emptyInfo = NetworkInfoSnapshot(
    interfaceName: '',
    localIpv4: '',
    privateDns: 'off',
    vpnActive: false,
  );
}

/// Tap-to-copy row for the address other devices should use. Kept as its own card so the action
/// reads as a button rather than as one more plain list row.
class _CopyCard extends StatelessWidget {
  const _CopyCard({required this.address, required this.withPort});

  final String address;
  final bool withPort;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    return DashboardDetailCard(
      semanticLabel: context.l10n.intranetCopyAddressSemantics(address),
      onTap: () => _copy(context, address),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: ShapeDecoration(
              color: colors.tone,
              shape: AppShape.all(AppCorner.sm),
            ),
            child: Center(
              child: GlyphIcon(
                AppGlyphs.copy,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  withPort ? context.l10n.intranetCopyAddressWithPort : context.l10n.intranetCopyAddress,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFeatures: appTabularFigures,
                      ),
                ),
              ],
            ),
          ),
          GlyphIcon(
            AppGlyphs.chevronForward,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  static Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.commonCopied(text)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }
}
