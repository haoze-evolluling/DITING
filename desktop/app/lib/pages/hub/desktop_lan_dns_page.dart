/// The `hub` branch's LAN DNS page: whether the resolver answers on `0.0.0.0:53`, which addresses a
/// router or a phone should point at, and whether the host firewall lets those packets in.
///
/// The old desktop console's `DevicesView` → `LanDnsCard.vue` is the functional blueprint. Turning the
/// service on also asks for the 53/tcp+udp rule, exactly as the console did; whether the host has a
/// firewall manager is `/dns/lan`'s answer, not a guess here.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_lan_models.dart';
import 'package:diting_desktop/data/api/desktop_lan_providers.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/widgets/desktop_copy_row.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopLanDnsPage extends ConsumerWidget {
  const DesktopLanDnsPage({super.key});

  static const path = '/hub/lan-dns';

  Future<void> _setAllowLan(
    BuildContext context,
    WidgetRef ref,
    bool allow,
  ) async {
    final l10n = context.l10n;
    final error = await ref.read(desktopLanProvider.notifier).setAllowLan(allow);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (allow ? l10n.desktopLanDnsOn : l10n.desktopLanDnsOff)
          : l10n.desktopLanDnsFailed(error.message),
    );
  }

  Future<void> _setFirewall(
    BuildContext context,
    WidgetRef ref,
    bool allowed,
  ) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopLanProvider.notifier)
        .setFirewall(allowed);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (allowed
                ? l10n.desktopLanDnsFirewallOn
                : l10n.desktopLanDnsFirewallOff)
          : l10n.desktopLanDnsFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopLanProvider);
    final status = state.status;
    void retry() => ref.read(desktopLanProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopLanDnsPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopLanDnsRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: status == null
          ? _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: retry,
            )
          : PageBody(
              children: [
                state.isStale
                    ? StaleStatusNotice(onRetry: retry)
                    : const SizedBox.shrink(),
                DesktopCardBoard(
                  cards: [
                    _ServiceCard(
                      status: status,
                      saving: state.saving,
                      onChanged: (allow) =>
                          unawaited(_setAllowLan(context, ref, allow)),
                    ),
                    _LanAddressesCard(status: status),
                    _FirewallCard(
                      status: status,
                      saving: state.saving,
                      onToggle: (allowed) =>
                          unawaited(_setFirewall(context, ref, allowed)),
                    ),
                    _RouterGuideCard(status: status),
                    _DeviceGuideCard(status: status),
                  ],
                ),
              ],
            ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.status,
    required this.saving,
    required this.onChanged,
  });

  final DesktopLanStatus status;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopLanDnsServiceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopLanDnsServiceTitle,
            leading: [
              DashboardChip(
                label: status.allowLan
                    ? l10n.desktopLanDnsOnChip
                    : l10n.desktopLanDnsOffChip,
                tone: status.allowLan
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: status.allowLan,
              ),
            ],
            trailing: [
              DashboardSwitch(
                value: status.allowLan,
                semanticLabel: l10n.desktopLanDnsServiceTitle,
                onChanged: saving ? null : onChanged,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopLanDnsServiceBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}


/// Where the LAN listener is bound and which address other devices should use.
///
/// This was the second half of the service card; it is its own card now, because a switch with three
/// address lists beside it made one card taller than the window.
class _LanAddressesCard extends StatelessWidget {
  const _LanAddressesCard({required this.status});

  final DesktopLanStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final first = status.lanAddresses.isEmpty ? null : status.lanAddresses.first;
    return DashboardCard(
      semanticLabel: l10n.desktopLanDnsAddressesCardTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.connections,
            title: l10n.desktopLanDnsAddressesCardTitle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopLanDnsAddressesCardBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.desktopLanDnsListenTitle,
            style: DashboardText.rowTitle(context),
          ),
          const SizedBox(height: 4),
          if (status.listenAddresses.isEmpty)
            Text(
              l10n.desktopLanDnsNoListen,
              style: DashboardText.label(context),
            )
          else
            for (final address in status.listenAddresses)
              DesktopCopyRow(value: address),
          const SizedBox(height: 12),
          Text(
            l10n.desktopLanDnsAddressesTitle,
            style: DashboardText.rowTitle(context),
          ),
          const SizedBox(height: 4),
          if (status.lanAddresses.isEmpty)
            Text(
              l10n.desktopLanDnsNoAddresses,
              style: DashboardText.label(context),
            )
          else
            for (final address in status.lanAddresses)
              DesktopCopyRow(
                value: address,
                tag: address.contains(':')
                    ? l10n.desktopLanDnsIpv6
                    : l10n.desktopLanDnsIpv4,
              ),
          if (first != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopLanDnsRouterHint(first),
              style: DashboardText.label(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _FirewallCard extends StatelessWidget {
  const _FirewallCard({
    required this.status,
    required this.saving,
    required this.onToggle,
  });

  final DesktopLanStatus status;
  final bool saving;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final supported = status.firewallSupported;
    return DashboardCard(
      semanticLabel: l10n.desktopLanDnsFirewallTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: l10n.desktopLanDnsFirewallTitle,
            leading: [
              DashboardChip(
                label: !supported
                    ? l10n.desktopLanDnsFirewallNone
                    : (status.firewallAllowed
                          ? l10n.desktopLanDnsFirewallAllowed
                          : l10n.desktopLanDnsFirewallBlocked),
                tone: !supported
                    ? DashboardChipTone.idle
                    : (status.firewallAllowed
                          ? DashboardChipTone.ok
                          : DashboardChipTone.warn),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            supported
                ? l10n.desktopLanDnsFirewallBody
                : l10n.desktopLanDnsFirewallNoneBody,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (supported) ...[
            const SizedBox(height: 12),
            DashboardBlock(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: Text(
                      status.firewallAllowed
                          ? l10n.desktopLanDnsFirewallStatusOn
                          : l10n.desktopLanDnsFirewallStatusOff,
                      style: DashboardText.rowTitle(context),
                    ),
                  ),
                  GlyphIcon(
                    status.firewallAllowed
                        ? AppGlyphs.checkCircle
                        : AppGlyphs.warning,
                    size: 20,
                    color: status.firewallAllowed
                        ? context.colorScheme.success
                        : context.colorScheme.warning,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: status.firewallAllowed
                  ? OutlinedButton.icon(
                      onPressed: saving ? null : () => onToggle(false),
                      icon: const GlyphIcon(AppGlyphs.block, size: 16),
                      label: Text(l10n.desktopLanDnsFirewallRemove),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: saving ? null : () => onToggle(true),
                      icon: const GlyphIcon(AppGlyphs.verified, size: 16),
                      label: Text(l10n.desktopLanDnsFirewallAllow),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouterGuideCard extends StatelessWidget {
  const _RouterGuideCard({required this.status});

  final DesktopLanStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopLanDnsRouterTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.wifi,
            title: l10n.desktopLanDnsRouterTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopLanDnsRouterBadge,
                tone: DashboardChipTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopLanDnsRouterBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 8),
          if (status.lanAddresses.isNotEmpty)
            DesktopCopyRow(value: status.lanAddresses.first)
          else
            Text(
              l10n.desktopLanDnsPlaceholder,
              style: DashboardText.label(context).toMonospace,
            ),
          const SizedBox(height: 8),
          Text(
            l10n.desktopLanDnsRouterFoot,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _DeviceGuideCard extends StatelessWidget {
  const _DeviceGuideCard({required this.status});

  final DesktopLanStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopLanDnsDeviceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: l10n.desktopLanDnsDeviceTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopLanDnsDeviceBadge,
                tone: DashboardChipTone.idle,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopLanDnsDeviceBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 8),
          if (status.lanAddresses.isNotEmpty)
            DesktopCopyRow(value: status.lanAddresses.first)
          else
            Text(
              l10n.desktopLanDnsPlaceholder,
              style: DashboardText.label(context).toMonospace,
            ),
          const SizedBox(height: 8),
          Text(
            l10n.desktopLanDnsDeviceFoot,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) return const Center(child: CommonCircleLoading.page());
    final unauthorized = error?.unauthorized ?? false;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: l10n.desktopLanDnsLoadFailed,
            description: unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : error?.message,
            action: FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.desktopRetry),
            ),
          ),
        ),
      ),
    );
  }
}
