/// Per-site latency breakdown, opened from the card's cell and from the detail page's rows.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:diting_android/state/primary_provider_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class SiteLatencyTargetSheet extends StatelessWidget {
  const SiteLatencyTargetSheet({
    super.key,
    required this.target,
    required this.summary,
    required this.lastRunAt,
  });

  final SiteLatencyTarget target;
  final PingSummary? summary;
  final DateTime? lastRunAt;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    String ms(double? value) => value == null ? '—' : '${value.round()} ms';
    return CommonScaffold(
      title: target.name,
      body: ListView(
        // The sheet title floats over the body, so this top padding is required.
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          ListHeader(title: context.l10n.siteLatencySheetLatency),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.link, size: 20),
            title: Text(context.l10n.siteLatencySheetCategory),
            trailing: Text(target.category.label(context.l10n)),
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.link, size: 20),
            title: Text(context.l10n.siteLatencySheetTarget),
            subtitle: Text(target.host),
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.speed, size: 20),
            title: Text(context.l10n.siteLatencySheetAverage),
            trailing: Text(ms(summary?.avgMs)),
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.arrowDown, size: 20),
            title: Text(context.l10n.siteLatencySheetMinMax),
            trailing: Text('${ms(summary?.minMs)} / ${ms(summary?.maxMs)}'),
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.motion, size: 20),
            title: Text(context.l10n.siteLatencySheetJitter),
            trailing: Text(ms(summary?.jitterMs)),
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.warning, size: 20),
            title: Text(context.l10n.siteLatencySheetLoss),
            trailing: Text(
              summary == null
                  ? '—'
                  : '${summary.lossPercent.toStringAsFixed(0)}%'
                        '（${summary.received}/${summary.transmitted}）',
            ),
          ),
          if (summary?.resolvedAddress case final address?
              when address.isNotEmpty)
            ListItem(
              leading: const GlyphIcon(AppGlyphs.dns, size: 20),
              title: Text(context.l10n.siteLatencySheetDns),
              subtitle: Text('${summary!.addressFamily ?? ''} $address'.trim()),
            ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.clock, size: 20),
            title: Text(context.l10n.siteLatencySheetLastRun),
            trailing: Text(elapsedAgoLabel(lastRunAt)),
          ),
          if (summary == null)
            ListFooter(text: context.l10n.siteLatencySheetNotTested)
          else if (!summary.success)
            ListFooter(
              text: summary.message?.isNotEmpty == true
                  ? summary.message!
                  : context.l10n.siteLatencySheetNoReply,
            )
          else if (summary.measuredWithFallback)
            ListFooter(text: context.l10n.siteLatencySheetFallbackFooter)
          else
            ListFooter(text: context.l10n.siteLatencySheetIcmpFooter),
        ],
      ),
    );
  }
}
