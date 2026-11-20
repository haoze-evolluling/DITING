library;

import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/native/dns_latency_bridge.dart';
import 'package:diting_android/routes/tools_paths.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/network_tools_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'tools_shared.dart';
part 'speed_test_page.dart';
part 'ping_test_page.dart';
part 'dns_lookup_page.dart';
part 'traceroute_page.dart';

enum NetworkTool {
  speedTest(AppGlyphs.speed, ToolPaths.speedTest),
  ping(AppGlyphs.connections, ToolPaths.ping),
  dnsLookup(AppGlyphs.dns, ToolPaths.dnsLookup),
  traceroute(AppGlyphs.split, ToolPaths.traceroute);

  const NetworkTool(this.glyph, this.path);

  final Glyph glyph;
  final String path;

  String label(AppL10n l10n) => switch (this) {
    speedTest => l10n.toolSpeedTest,
    ping => l10n.toolPing,
    dnsLookup => l10n.toolDnsLookup,
    traceroute => l10n.toolTraceroute,
  };

  String description(AppL10n l10n) => switch (this) {
    speedTest => l10n.toolSpeedTestDesc,
    ping => l10n.toolPingDesc,
    dnsLookup => l10n.toolDnsLookupDesc,
    traceroute => l10n.toolTracerouteDesc,
  };
}

class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.toolDiagnostics,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: l10n.toolRefreshInfo,
          onPressed: () => ref.invalidate(networkInfoProvider),
        ),
      ],
      body: PageBody(
        children: [
          ListHeader(title: l10n.toolOverviewTitle),
          const _NetworkOverviewCard(),
          generateSection(
            title: l10n.toolToolsSection,
            items: [
              for (final tool in NetworkTool.values) _ToolEntry(tool: tool),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolEntry extends StatelessWidget {
  const _ToolEntry({required this.tool});

  final NetworkTool tool;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListItem(
      leading: _ToolBadge(glyph: tool.glyph),
      title: Text(tool.label(l10n)),
      subtitle: Text(tool.description(l10n)),
      trailing: const GlyphIcon(AppGlyphs.chevronForward),
      onTap: () => context.push(tool.path),
    );
  }
}

class _ToolBadge extends StatelessWidget {
  const _ToolBadge({required this.glyph});

  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: AppShape.standard,
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
      ),
      child: GlyphIcon(glyph, size: 20, color: colorScheme.primary),
    );
  }
}

class _NetworkOverviewCard extends ConsumerWidget {
  const _NetworkOverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final info = ref.watch(networkInfoProvider).value;
    final hasAddress = info?.localIpv4.isNotEmpty ?? false;
    final hasDns = info?.dnsServers.isNotEmpty ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CommonCard(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
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
                  value: hasAddress ? info!.localIpv4 : '—',
                ),
                StatItem(
                  label: context.l10n.toolDnsServers,
                  value: hasDns ? '${info!.dnsServers.length}' : '—',
                  unit: hasDns ? context.l10n.toolCountUnit : null,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: AppShape.standard,
                  color: context.raisedSurfaceLevel.colorOf(colorScheme),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
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
                              ? context.l10n.toolPrivateDnsProbe(
                                  info.privateDns,
                                )
                              : context.l10n.toolPhysicalProbe,
                          style: AppTextRole.supportingText.of(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
