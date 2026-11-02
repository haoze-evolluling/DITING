import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
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
                ListFooter(
                  text:
                      context.l10n.logsSubStatsFooter,
                ),
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
    final colorScheme = context.colorScheme;

    if (snapshot.missingColumn) {
      return lazySectionSlivers(
        title: context.l10n.logsBlockingSubs,
        itemCount: 1,
        itemBuilder: (context, _) => ListItem(
          leading: GlyphIcon(AppGlyphs.warning, color: colorScheme.warning),
          title: Text(context.l10n.logsMissingSubColumn),
          subtitle: Text(
            context.l10n.logsMissingSubColumnBody,
          ),
        ),
      );
    }

    return [
      SliverToBoxAdapter(
        child: generateSection(
          title: context.l10n.logsOverview,
          items: [
            StatStrip(
              stats: [
                StatItem(
                  label: context.l10n.logsAllRecordedRequests,
                  value: countOf(snapshot.totalRequests),
                ),
              ],
            ),
          ],
          footer: context.l10n.logsAllRecordedFooter,
        ),
      ),
      if (snapshot.items.isEmpty)
        SliverToBoxAdapter(
          child: generateSection(
            title: context.l10n.logsBlockingSubs,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.rules),
                title: Text(context.l10n.logsNoBlockingSubs),
                subtitle: Text(context.l10n.logsNoBlockingSubsBody),
              ),
            ],
          ),
        )
      else
        ...lazySectionSlivers(
          title: context.l10n.logsBlockingSubs,
          itemCount: snapshot.items.length,
          footer: context.l10n.logsBlockingSubsFooter,
          itemBuilder: (context, index) {
            final item = snapshot.items[index];
            return ListItem(
              leading: GlyphIcon(
                item.deleted ? AppGlyphs.warning : AppGlyphs.rules,
                color: item.deleted
                    ? colorScheme.onSurfaceVariant
                    : (item.enabled ? colorScheme.primary : null),
              ),
              title: Text(item.name),
              subtitle: Text(
                context.l10n.logsSubStatsRow(
                  item.statusLabel,
                  countOf(item.hits),
                  percentOf(item.rate),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                percentOf(item.rate),
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            );
          },
        ),
    ];
  }
}
