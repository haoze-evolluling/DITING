/// The newest queries, in the space upstream fills with its connections table. Read-only: the log
/// page owns search and paging.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/pages/home/desktop_format.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_density.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RecentQueriesCard extends ConsumerWidget {
  const RecentQueriesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final entries = ref.watch(desktopRecentQueriesProvider);
    final density = DashboardDensityScope.of(context);
    return DashboardCard(
      semanticLabel: l10n.desktopRecentQueriesTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.connections,
            title: l10n.desktopRecentQueriesTitle,
            leading: [
              DashboardChip(
                label: '${entries.length}',
                tone: DashboardChipTone.idle,
              ),
            ],
          ),
          SizedBox(height: 10 * DashboardDensityScope.scaleOf(context)),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l10n.desktopRecentQueriesEmpty,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(context),
              ),
            )
          else
            // Shrink-wrapped so a card in a stacked column takes only its rows, and scrollable so
            // the same card in the fixed row cannot overflow.
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, index) =>
                    _QueryRow(entry: entries[index], density: density),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueryRow extends StatelessWidget {
  const _QueryRow({required this.entry, required this.density});

  final QueryLogEntry entry;
  final DashboardDensity density;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final (glyph, color, label) = switch (entry) {
      QueryLogEntry(blocked: true) => (
        AppGlyphs.block,
        colorScheme.warning,
        l10n.statusBlocked,
      ),
      QueryLogEntry(cached: true) => (
        AppGlyphs.checkCircle,
        colorScheme.success,
        l10n.logRowCacheHit,
      ),
      _ => (AppGlyphs.arrowUp, colorScheme.onSurfaceVariant, entry.status),
    };
    return SizedBox(
      height: density.isCompact ? 26 : 30,
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(glyph, size: 16, color: color),
          Expanded(
            flex: 5,
            child: Text(
              entry.displayDomain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.rowTitle(context),
            ),
          ),
          if (entry.qtype.isNotEmpty)
            SizedBox(
              width: 44,
              child: Text(
                entry.qtype,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(context),
              ),
            ),
          Expanded(
            flex: 3,
            child: Text(
              entry.client,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: DashboardText.label(context),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              entry.durationMs > 0 ? desktopLatency(entry.durationMs) : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: DashboardText.label(context),
            ),
          ),
        ],
      ),
    );
  }
}
