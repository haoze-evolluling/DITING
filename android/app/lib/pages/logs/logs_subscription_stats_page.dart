import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/logs/logs_overview_card.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Subscription rule block rate. Numerator counts BLOCKED DNS rows and blocked/invalid HTTPS
/// rows carrying a blockSubscriptionId, matching upstream; missing data is never invented.
class LogsSubscriptionStatsPage extends ConsumerWidget {
  const LogsSubscriptionStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStats = ref.watch(subscriptionInterceptionProvider);
    final range = ref.watch(subscriptionStatsRangeProvider);
    return CommonScaffold(
      title: context.l10n.logsSubStatsTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.logsRefresh,
          onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: SliverPageBody(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                generateSection(
                  title: context.l10n.logsTimeRange,
                  items: [
                    LogStatsRangeSelector<SubscriptionStatsRange>(
                      values: SubscriptionStatsRange.values,
                      labelOf: (option) => option.label(context.l10n),
                      value: range,
                      onChanged: (value) => ref
                          .read(subscriptionStatsRangeProvider.notifier)
                          .select(value),
                    ),
                  ],
                ),
                ListFooter(text: context.l10n.logsSubStatsFooter),
              ],
            ),
          ),
          ..._statsSlivers(context, asyncStats),
        ],
      ),
    );
  }

  /// Stats sections as slivers. The per-subscription list is built on demand: the table grows
  /// with the number of imported subscriptions, and inflating it eagerly was the same first-frame
  /// trap the rule lists hit.
  List<Widget> _statsSlivers(
    BuildContext context,
    AsyncValue<SubscriptionInterceptionSnapshot> asyncStats,
  ) {
    if (!asyncStats.hasValue) {
      if (asyncStats.hasError) {
        return lazySectionSlivers(
          title: context.l10n.logsOverview,
          itemCount: 1,
          itemBuilder: (context, _) => ListItem(
            leading: const GlyphIcon(AppGlyphs.error),
            title: Text(context.l10n.logsSubStatsLoadFailed),
            subtitle: Text('${asyncStats.error}'),
          ),
        );
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: LogsPageLoading(label: context.l10n.logsLoadingStats),
          ),
        ),
      ];
    }
    final snapshot = asyncStats.requireValue;
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;

    if (snapshot.missingColumn) {
      return lazySectionSlivers(
        title: l10n.logsBlockingSubs,
        itemCount: 1,
        itemBuilder: (context, _) => ListItem(
          leading: GlyphIcon(AppGlyphs.warning, color: colorScheme.warning),
          title: Text(l10n.logsMissingSubColumn),
          subtitle: Text(l10n.logsMissingSubColumnBody),
        ),
      );
    }

    // The numerator is exactly the per-subscription hit total, so the page never shows two
    // different block counts side by side.
    final blocked = snapshot.items.fold(0, (sum, item) => sum + item.hits);
    final hasData = snapshot.totalRequests > 0;
    final passed = snapshot.totalRequests - blocked;

    return [
      SliverToBoxAdapter(
        child: generateSection(
          title: l10n.logsOverview,
          items: [
            LogsOverviewCard(
              tiles: [
                LogsOverviewTile(
                  label: l10n.logsAllRecordedRequests,
                  value: countOf(snapshot.totalRequests),
                  glyph: AppGlyphs.requests,
                  color: colorScheme.primary,
                ),
                LogsOverviewTile(
                  label: l10n.logsBlockedRequests,
                  value: countOf(blocked),
                  glyph: AppGlyphs.block,
                  color: hasData && blocked > 0
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
              ],
              ratio: hasData
                  ? LogsRatioBar(
                      label: l10n.trafficStructureBlockRate,
                      value: percentOf(blocked / snapshot.totalRequests),
                      segments: [
                        (value: blocked, color: colorScheme.error),
                        (
                          value: passed < 0 ? 0 : passed,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ],
          footer: l10n.logsAllRecordedFooter,
        ),
      ),
      if (snapshot.items.isEmpty)
        SliverToBoxAdapter(
          child: generateSection(
            title: l10n.logsBlockingSubs,
            items: [
              LogsSectionEmpty(
                glyph: AppGlyphs.rules,
                title: l10n.logsNoBlockingSubs,
                description: l10n.logsNoBlockingSubsBody,
              ),
            ],
          ),
        )
      else
        ...lazySectionSlivers(
          title: l10n.logsBlockingSubs,
          itemCount: snapshot.items.length,
          footer: l10n.logsBlockingSubsFooter,
          itemBuilder: (context, index) {
            final item = snapshot.items[index];
            final dimmed = item.deleted || !item.enabled;
            return ListItem(
              leading: IconBadge(
                glyph: item.deleted ? AppGlyphs.warning : AppGlyphs.rules,
                // The row card owns the card level; the badge needs the next one up.
                color: SurfaceLevel.block.colorOf(colorScheme),
                foregroundColor: item.deleted
                    ? colorScheme.onSurfaceVariant
                    : (item.enabled ? colorScheme.primary : null),
                shape: AppShape.circle,
                size: 34,
                glyphSize: 17,
              ),
              title: Text(item.name),
              subtitle: Text(
                l10n.logsSubStatsRow(item.statusLabel, countOf(item.hits)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // The rate is the page's subject, so it gets the figure slot on the right instead
              // of repeating the same percentage inside the subtitle.
              trailing: Text(
                percentOf(item.rate),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .toTabular
                    .copyWith(
                      color: dimmed
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.primary,
                    ),
              ),
            );
          },
        ),
    ];
  }
}
