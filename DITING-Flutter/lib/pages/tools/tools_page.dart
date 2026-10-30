/// Network diagnostics: four tabs; `Stack` + `Offstage` keeps each tab state.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/native/diagnostics_bridge.dart';
import 'package:diting/data/native/dns_latency_bridge.dart';
import 'package:diting/state/diagnostics_providers.dart';
import 'package:diting/state/network_tools_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/page_intro.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'tools_dns_panel.dart';
part 'tools_panels.dart';
part 'tools_ping_panel.dart';
part 'tools_speed_panel.dart';
part 'tools_trace_panel.dart';

enum NetworkTool {
  speedTest(AppGlyphs.speed),
  ping(AppGlyphs.connections),
  dnsLookup(AppGlyphs.dns),
  traceroute(AppGlyphs.split);

  const NetworkTool(this.glyph);

  final Glyph glyph;

  String label(AppL10n l10n) => switch (this) {
    speedTest => l10n.toolSpeedTest,
    ping => l10n.toolPing,
    dnsLookup => l10n.toolDnsLookup,
    traceroute => l10n.toolTraceroute,
  };
}

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  /// The default tab matches the legacy view model, which starts on `PING` even though
  /// `SPEED_TEST` is declared first.
  var _tool = NetworkTool.ping;

  /// Tabs built so far. A tab is built on its first visit and then kept, so entering the page lays
  /// out one panel instead of four (about 14 ms of a 20 ms first frame on the emulator).
  final _visited = <NetworkTool>{NetworkTool.ping};

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.toolDiagnostics,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.toolRefreshInfo,
          onPressed: () => ref.invalidate(networkInfoProvider),
        ),
      ],
      body: AppBarClearance(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _NetworkOverviewCard(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SegmentedControl<NetworkTool>(
                segments: [
                  for (final tool in NetworkTool.values)
                    (tool, tool.label(context.l10n)),
                ],
                value: _tool,
                onChanged: (tool) => setState(() {
                  _tool = tool;
                  _visited.add(tool);
                }),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  for (final tool in NetworkTool.values)
                    Offstage(
                      offstage: tool != _tool,
                      child: TickerMode(
                        enabled: tool == _tool,
                        // Every slot stays in the list so a visited panel keeps its element.
                        child: !_visited.contains(tool)
                            ? const SizedBox.shrink()
                            : switch (tool) {
                                NetworkTool.speedTest =>
                                  const _SpeedTestPanel(),
                                NetworkTool.ping => const _PingPanel(),
                                NetworkTool.dnsLookup => _DnsLookupPanel(),
                                NetworkTool.traceroute =>
                                  const _TraceroutePanel(),
                              },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Current network" overview: type, local addresses and DNS servers. Vertical space is scarce
/// because all four tabs sit below, so the legacy expandable card is collapsed into one line.
class _NetworkOverviewCard extends ConsumerWidget {
  const _NetworkOverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final info = ref.watch(networkInfoProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            StatStrip(
              stats: [
                StatItem(
                  label: context.l10n.toolActiveInterface,
                  value: info == null ? '—' : networkInterfaceLabel(info),
                  color: info?.vpnActive == true
                      ? colorScheme.warning
                      : colorScheme.success,
                ),
                StatItem(
                  label: context.l10n.toolLocalAddress,
                  value: (info?.localIpv4.isNotEmpty ?? false)
                      ? info!.localIpv4
                      : '—',
                ),
                StatItem(
                  label: context.l10n.toolDnsServers,
                  value: (info?.dnsServers.isNotEmpty ?? false)
                      ? '${info!.dnsServers.length}'
                      : '—',
                  unit: (info?.dnsServers.isNotEmpty ?? false)
                      ? context.l10n.toolCountUnit
                      : null,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  GlyphIcon(
                    AppGlyphs.info,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Text(
                      info != null && info.privateDns != 'off'
                          ? context.l10n.toolPrivateDnsProbe(info.privateDns)
                          : context.l10n.toolPhysicalProbe,
                      style: context.listCaptionStyle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
