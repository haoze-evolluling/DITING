import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/home/widgets/home_power_button.dart';
import 'package:diting_android/pages/server/server_actions.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/server_upstream_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Server mode "overview" tab (upstream `server/ui/DnsHomeScreen.kt`): power plus status text,
/// current upstream, LAN access, service stats and a footer, all from `serverStatusProvider`.
class ServerOverviewPage extends ConsumerWidget {
  const ServerOverviewPage({
    super.key,
    required this.onOpenUpstreams,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenUpstreams;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider);
    final port = ref.watch(serverPortProvider);
    final stats = ref.watch(serviceStatsProvider);
    final upstream = ref.watch(serverSelectedUpstreamProvider);
    final network = ref.watch(networkInfoProvider);
    final running = status == ServerStatus.running;
    final localIpv4 = network.asData?.value.localIpv4 ?? '';
    return CommonScaffold(
      title: context.l10n.serverOverviewTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.swap,
          tooltip: context.l10n.serverSwitchMode,
          onPressed: () => context.push(Routes.modeSelect),
        ),
        IconButtonData(
          glyph: AppGlyphs.sliders,
          tooltip: context.l10n.serverChangePort,
          onPressed: () => editServerPort(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          _PowerArea(status: status, port: port),
          _StatusText(status: status),
          const SizedBox(height: 8),
          generateSection(
            title: context.l10n.serverCurrentUpstreamCard,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.dns,
                title: upstream.name,
                subtitle: upstream.endpointLabel,
                onPressed: onOpenUpstreams,
              ),
            ],
          ),
          const SizedBox(height: 6),
          generateSection(
            title: context.l10n.serverLanAccess,
            // The port binds at startup only: changing it without a restart shows an
            // address nobody listens on and LAN devices time out.
            footer:
                context.l10n.serverLanBody,
            items: [
              ListItem(
                title: Text(
                  localIpv4.isEmpty ? context.l10n.serverNoNetwork : '$localIpv4:$port',
                  style: context.listTitleStyle.copyWith(
                    fontFamily: appMonospaceFontFamily,
                  ),
                ),
                subtitle: Text(
                  localIpv4.isEmpty
                      ? context.l10n.serverLanConnectHint
                      : context.l10n.serverLanPointHint,
                ),
                leading: GlyphIcon(
                  localIpv4.isEmpty ? AppGlyphs.wifiOff : AppGlyphs.wifi,
                ),
                trailing: localIpv4.isEmpty
                    ? null
                    : GlyphIcon(
                        AppGlyphs.copy,
                        color: context.colorScheme.primary,
                      ),
                onTap: localIpv4.isEmpty
                    ? null
                    : () async {
                        // Write the clipboard before reporting: a bare "copied" leaves the
                        // user with an empty clipboard.
                        final address = '$localIpv4:$port';
                        await Clipboard.setData(ClipboardData(text: address));
                        if (!context.mounted) {
                          return;
                        }
                        showServerHint(
                          context,
                          context.l10n.serverCopied(address),
                        );
                      },
              ),
            ],
          ),
          const SizedBox(height: 6),
          ListHeader(title: context.l10n.serverServiceStatus),
          // The stat strip sits directly in `PageBody` without `generateSection`, so it
          // supplies its own horizontal padding.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CommonCard(
              padding: EdgeInsets.zero,
              child: StatStrip(
                stats: [
                  StatItem(label: context.l10n.serverTotalQueries, value: '${stats.queries}'),
                  StatItem(
                    label: context.l10n.serverCacheHits,
                    value: '${stats.cacheHits}',
                    color: context.colorScheme.primary,
                  ),
                  StatItem(
                    label: context.l10n.serverBlocked,
                    value: '${stats.blocked}',
                    color: context.colorScheme.error,
                  ),
                  StatItem(
                    label: context.l10n.serverAverageLatency,
                    // The legacy version read `DnsModeStats.latencyMs`, which
                    // `EngineStats.snapshot` lacks, so this
                    // shows a dash rather than 0 or a mock number.
                    value: '--',
                    unit: 'ms',
                  ),
                  StatItem(
                    label: context.l10n.serverUptime,
                    value: running ? stats.uptimeLabel : '--',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          generateSection(
            items: [
              NavEntryRow(
                glyph: AppGlyphs.reset,
                title: context.l10n.serverResetStats,
                subtitle: context.l10n.serverResetStatsBodyShort,
                onPressed: () => confirmResetServerStats(context, ref),
              ),
              NavEntryRow(
                glyph: AppGlyphs.settings,
                title: context.l10n.serverModeSettings,
                subtitle: context.l10n.serverModeSettingsBody,
                onPressed: onOpenSettings,
              ),
            ],
          ),
          ListFooter(
            text:
                context.l10n.serverModeNote,
          ),
        ],
      ),
    );
  }
}

/// Power area reusing [HomePowerButton] with two overridden labels. The explicit switch is
/// required: `PowerState` and `ServerStatus` both have five states with different labels.
class _PowerArea extends ConsumerWidget {
  const _PowerArea({required this.status, required this.port});

  final ServerStatus status;
  final int port;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy =
        status == ServerStatus.starting || status == ServerStatus.stopping;
    return Column(
      children: [
        const SizedBox(height: 4),
        HomePowerButton(
          state: _powerStateOf(status),
          busyLabel: busy ? context.l10n.serverBusyStarting : context.l10n.serverBusyStopping,
          runningLabel: context.l10n.serverRunning,
          stoppedLabel: context.l10n.serverStopped,
          onPressed: () => ref.read(serverStatusProvider.notifier).toggle(),
        ),
        Text(
          context.l10n.serverListening('$port'),
          style: context.listCaptionStyle.copyWith(
            fontFamily: appMonospaceFontFamily,
          ),
        ),
      ],
    );
  }

  static PowerState _powerStateOf(ServerStatus status) => switch (status) {
    ServerStatus.stopped => PowerState.stopped,
    ServerStatus.starting => PowerState.starting,
    ServerStatus.running => PowerState.running,
    ServerStatus.stopping => PowerState.stopping,
    ServerStatus.error => PowerState.error,
  };
}

/// Five-state status text; colour and wording follow the state. A separate line because the
/// button only conveys "tappable" and a failure needs a readable sentence.
class _StatusText extends StatelessWidget {
  const _StatusText({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (text, color) = switch (status) {
      ServerStatus.stopped => (context.l10n.serverStatusStopped, colorScheme.onSurfaceVariant),
      ServerStatus.starting => (context.l10n.serverStatusStarting, colorScheme.primary),
      ServerStatus.running => (context.l10n.serverStatusRunning, colorScheme.primary),
      ServerStatus.stopping => (context.l10n.serverStatusStopping, colorScheme.onSurfaceVariant),
      ServerStatus.error => (context.l10n.serverStatusErrorText, colorScheme.error),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(color: color),
      ),
    );
  }
}
