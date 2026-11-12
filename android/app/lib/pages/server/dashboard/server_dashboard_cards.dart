import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/server_dashboard_widgets.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_android/pages/server/server_actions.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/server_resolution_providers.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/server_upstream_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Builds one server-home dashboard card. [interactive] is false in edit mode, where no card
/// navigates: leaving the page mid-arrangement reads as a lost drag (same rule as the log board).
Widget buildServerDashboardCard(
  BuildContext context,
  ServerDashboardWidget widget, {
  bool interactive = true,
}) {
  VoidCallback? push(String path) =>
      interactive ? () => context.push(path) : null;
  return switch (widget) {
    ServerDashboardWidget.lanAccess => const _ServerLanAccessCard(),
    ServerDashboardWidget.status => _ServerStatusCard(interactive: interactive),
    ServerDashboardWidget.upstream => _ServerUpstreamCard(
      onOpen: push(ServerPaths.upstream),
    ),
    ServerDashboardWidget.cache => _ServerCacheCard(
      onOpen: push(HubPaths.cache),
    ),
    ServerDashboardWidget.ruleControl => _ServerRuleControlCard(
      onOpen: push(HubPaths.ruleControl),
    ),
    ServerDashboardWidget.domainRules => _ServerDomainRulesCard(
      onBlock: push(Routes.rulesOf('block')),
      onAllow: push(Routes.rulesOf('allow')),
      onHosts: push(Routes.rulesOf('rewrite')),
    ),
  };
}

/// LAN address peers should point their DNS at. The port only appears while the server is
/// listening: a stopped server binds nothing, so "ip:port" would be an address nobody answers on.
class _ServerLanAccessCard extends ConsumerWidget {
  const _ServerLanAccessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkInfoProvider);
    final localIp = network.asData?.value.localIpv4 ?? '';
    final loading = network.isLoading;
    final listening = ref.watch(serverStatusProvider) == ServerStatus.running;
    final port = ref.watch(serverPortProvider);
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    final address = localIp.isEmpty
        ? null
        : listening
        ? '$localIp:$port'
        : localIp;
    final hint = localIp.isEmpty
        ? context.l10n.serverLanConnectHint
        : listening
        ? context.l10n.serverLanPointHint
        : context.l10n.intranetServiceStopped(port);
    return DashboardCard(
      semanticLabel: context.l10n.serverLanAccess,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: context.l10n.serverLanAccess,
            trailing: [
              DashboardIconButton(
                glyph: AppGlyphs.copy,
                tooltip: context.l10n.intranetCopyAddress,
                onPressed: address == null
                    ? null
                    : () => _copy(context, address),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          Text(
            address ??
                (loading
                    ? context.l10n.intranetReading
                    : context.l10n.serverNoNetwork),
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
          SizedBox(height: 10 * scale),
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
                  color: listening
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 2,
                    style: DashboardText.label(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    showServerHint(context, context.l10n.serverCopied(text));
  }
}

/// Service state, uptime and this run's counters.
class _ServerStatusCard extends ConsumerWidget {
  const _ServerStatusCard({required this.interactive});

  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider);
    final running = status == ServerStatus.running;
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    final (tone, label) = switch (status) {
      ServerStatus.running => (
        DashboardChipTone.ok,
        status.label(context.l10n),
      ),
      ServerStatus.starting || ServerStatus.stopping => (
        DashboardChipTone.idle,
        status.label(context.l10n),
      ),
      ServerStatus.error => (
        DashboardChipTone.warn,
        status.label(context.l10n),
      ),
      ServerStatus.stopped => (
        DashboardChipTone.idle,
        status.label(context.l10n),
      ),
    };
    return DashboardCard(
      semanticLabel: context.l10n.serverServiceStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.status,
            title: context.l10n.serverServiceStatus,
            leading: [DashboardChip(label: label, tone: tone, dot: true)],
            trailing: [
              if (interactive)
                DashboardIconButton(
                  glyph: AppGlyphs.reset,
                  tooltip: context.l10n.serverResetStats,
                  onPressed: () => confirmResetServerStats(context, ref),
                ),
            ],
          ),
          SizedBox(height: 12 * scale),
          Text(context.l10n.serverUptime, style: DashboardText.label(context)),
          SizedBox(height: 2 * scale),
          if (running)
            Consumer(
              builder: (context, ref, _) => Text(
                ref.watch(serviceStatsProvider.select((s) => s.uptimeLabel)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.figure(
                  context,
                  AppTextStyle.title1,
                  color: colorScheme.onSurface,
                ),
              ),
            )
          else
            Text(
              '--',
              style: DashboardText.figure(
                context,
                AppTextStyle.title1,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          SizedBox(height: 14 * scale),
          Consumer(
            builder: (context, ref, _) {
              final stats = ref.watch(serviceStatsProvider);
              return DashboardMetricGrid(
                maxColumns: 2,
                metrics: [
                  DashboardMetric(
                    label: context.l10n.serverTotalQueries,
                    value: '${stats.queries}',
                  ),
                  DashboardMetric(
                    label: context.l10n.serverCacheHits,
                    value: '${stats.cacheHits}',
                    color: colorScheme.primary,
                  ),
                  DashboardMetric(
                    label: context.l10n.serverBlocked,
                    value: '${stats.blocked}',
                    color: colorScheme.error,
                  ),
                  DashboardMetric(
                    // The engine snapshot has no latency figure; a hit rate is the honest
                    // "is it working" number at a glance and avoids a permanent dash.
                    label: context.l10n.statusCacheHitRate,
                    value: stats.queries == 0
                        ? '--'
                        : dashboardPercent(stats.cacheHitRate),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Resolution mode plus the selected upstream (or the race candidate count); taps open the editor.
class _ServerUpstreamCard extends ConsumerWidget {
  const _ServerUpstreamCard({required this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upstream = ref.watch(serverSelectedUpstreamProvider);
    final resolution = ref.watch(serverResolutionModeProvider);
    final raceIds = ref.watch(serverRaceProvidersProvider);
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    final single = resolution.isSingle;
    return DashboardCard(
      semanticLabel: context.l10n.serverCurrentUpstreamCard,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: context.l10n.serverCurrentUpstreamCard,
            leading: [DashboardChip(label: resolution.label(context.l10n))],
            trailing: [
              GlyphIcon(
                AppGlyphs.chevronForward,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          Text(
            single
                ? upstream.name
                : context.l10n.resolutionProviderCount(raceIds.length),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.figure(
              context,
              AppTextStyle.subheadline,
              color: colorScheme.onSurface,
            ).copyWith(letterSpacing: 0),
          ),
          SizedBox(height: 2 * scale),
          Text(
            single ? upstream.endpointLabel : resolution.label(context.l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

/// Cache switch and preset summary; taps open the cache settings page.
class _ServerCacheCard extends ConsumerWidget {
  const _ServerCacheCard({required this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final enabled = settings.serverCacheEnabled;
    final preset = serverCachePresetLabel(
      settings.serverCachePresetRaw,
      context.l10n,
    );
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: context.l10n.serverCacheSettings,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.memory,
            title: context.l10n.serverCacheSettings,
            leading: [
              DashboardChip(
                label: enabled
                    ? context.l10n.commonEnabled
                    : context.l10n.commonDisabled,
                tone: enabled ? DashboardChipTone.ok : DashboardChipTone.idle,
              ),
            ],
            trailing: [
              GlyphIcon(
                AppGlyphs.chevronForward,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            enabled
                ? context.l10n.serverCacheOn(preset)
                : context.l10n.serverCacheOff,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

/// Rule master switch summary; taps open the rule control page.
class _ServerRuleControlCard extends ConsumerWidget {
  const _ServerRuleControlCard({required this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final enabled = settings.serverAdBlockEnabled;
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: context.l10n.serverRuleControl,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: context.l10n.serverRuleControl,
            leading: [
              DashboardChip(
                label: enabled
                    ? context.l10n.commonEnabled
                    : context.l10n.commonDisabled,
                tone: enabled ? DashboardChipTone.ok : DashboardChipTone.idle,
              ),
            ],
            trailing: [
              GlyphIcon(
                AppGlyphs.chevronForward,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            enabled
                ? context.l10n.serverRuleControlOn
                : context.l10n.serverRuleControlOff,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

/// Shortcuts to the three domain-rule tables. One card keeps the three related entries together
/// instead of spending three full cards on navigation-only rows.
class _ServerDomainRulesCard extends StatelessWidget {
  const _ServerDomainRulesCard({
    required this.onBlock,
    required this.onAllow,
    required this.onHosts,
  });

  final VoidCallback? onBlock;
  final VoidCallback? onAllow;
  final VoidCallback? onHosts;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      semanticLabel: context.l10n.serverDomainRules,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: context.l10n.serverDomainRules,
          ),
          const SizedBox(height: 4),
          _RuleEntry(
            glyph: AppGlyphs.block,
            title: context.l10n.serverBlocklist,
            onTap: onBlock,
            first: true,
          ),
          _RuleEntry(
            glyph: AppGlyphs.verified,
            title: context.l10n.serverAllowlist,
            onTap: onAllow,
          ),
          _RuleEntry(
            glyph: AppGlyphs.swap,
            title: context.l10n.serverHosts,
            onTap: onHosts,
          ),
        ],
      ),
    );
  }
}

class _RuleEntry extends StatelessWidget {
  const _RuleEntry({
    required this.glyph,
    required this.title,
    required this.onTap,
    this.first = false,
  });

  final Glyph glyph;
  final String title;
  final VoidCallback? onTap;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first)
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppCorner.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            child: Row(
              spacing: 10,
              children: [
                GlyphIcon(glyph, size: 18, color: colorScheme.primary),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.rowTitle(context)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                ),
                GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
