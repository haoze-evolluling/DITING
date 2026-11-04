import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/logs/logs_overview_card.dart';
import 'package:diting_android/pages/logs/logs_row_marks.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_race_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Race stats from the real `dns_race_log` table, aggregated per time window. An empty
/// table leaves every section empty and the overview at a dash, never demo numbers.
class LogsRacePage extends ConsumerWidget {
  const LogsRacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStats = ref.watch(raceStatsProvider);
    final range = ref.watch(raceStatsRangeProvider);
    return CommonScaffold(
      title: context.l10n.logsRaceTitle,
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
            child: generateSection(
              title: context.l10n.logsTimeRange,
              items: [
                LogStatsRangeSelector<LogStatsRange>(
                  values: LogStatsRange.values,
                  labelOf: (range) => range.label(context.l10n),
                  value: range,
                  onChanged: (value) =>
                      ref.read(raceStatsRangeProvider.notifier).select(value),
                ),
              ],
            ),
          ),
          ..._statsSlivers(context, asyncStats, range),
          SliverToBoxAdapter(
            child: ListFooter(text: context.l10n.logsRaceFooter),
          ),
        ],
      ),
    );
  }

  /// Stats sections as slivers. The ranking and the strategy lists are built on demand: they grow
  /// with the number of configured resolvers, and eager construction is the same first-frame trap
  /// the rule lists hit with a large subscription.
  List<Widget> _statsSlivers(
    BuildContext context,
    AsyncValue<RaceStatsSnapshot> asyncStats,
    LogStatsRange range,
  ) {
    if (!asyncStats.hasValue) {
      if (asyncStats.hasError) {
        return lazySectionSlivers(
          title: context.l10n.logsOverview,
          itemCount: 1,
          itemBuilder: (context, _) => ListItem(
            leading: const GlyphIcon(AppGlyphs.error),
            title: Text(context.l10n.logsRaceLoadFailed),
            subtitle: Text('${asyncStats.error}'),
          ),
        );
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: LogsPageLoading(label: context.l10n.logsLoadingRace),
          ),
        ),
      ];
    }
    final l10n = context.l10n;
    final snapshot = asyncStats.requireValue;
    final summary = snapshot.summary;
    final colorScheme = context.colorScheme;
    final hasData = summary.requests > 0;

    return [
      SliverToBoxAdapter(
        child: generateSection(
          title: l10n.logsOverview,
          footer: hasData
              ? l10n.logsRaceSummary(
                  range.label(l10n),
                  countOf(summary.requests),
                )
              : l10n.logsRaceEmptyRange,
          items: [
            LogsOverviewCard(
              tiles: [
                LogsOverviewTile(
                  label: l10n.logsRaceRequests,
                  value: countOf(summary.requests),
                  glyph: AppGlyphs.shuffle,
                  color: colorScheme.primary,
                ),
                LogsOverviewTile(
                  label: l10n.logsSuccess,
                  value: hasData ? countOf(summary.successes) : '—',
                  glyph: AppGlyphs.check,
                  color: hasData
                      ? colorScheme.success
                      : colorScheme.onSurfaceVariant,
                ),
                LogsOverviewTile(
                  label: l10n.commonFailed,
                  value: hasData ? countOf(summary.failures) : '—',
                  glyph: AppGlyphs.close,
                  color: hasData && summary.failures > 0
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
                LogsOverviewTile(
                  label: l10n.logsAverageElapsed,
                  value: hasData ? millisOf(summary.averageLatencyMs) : '—',
                  glyph: AppGlyphs.speed,
                ),
              ],
              // The success share only says something once a race ran; before that the bar
              // would draw an empty track under a meaningless `—`.
              ratio: hasData
                  ? LogsRatioBar(
                      label: l10n.logsSuccessRate,
                      value: percentOf(summary.successes / summary.requests),
                      segments: [
                        (value: summary.successes, color: colorScheme.success),
                        (value: summary.failures, color: colorScheme.error),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
      if (snapshot.strategyStats.isNotEmpty)
        ...lazySectionSlivers(
          title: l10n.logsStrategyOverview,
          itemCount: snapshot.strategyStats.length,
          footer: l10n.logsStrategyFooter,
          itemBuilder: (context, index) {
            final item = snapshot.strategyStats[index];
            return ListItem(
              leading: IconBadge(
                glyph: _strategyGlyph(item.strategy),
                color: SurfaceLevel.block.colorOf(colorScheme),
                foregroundColor: colorScheme.primary,
                shape: AppShape.circle,
                size: 34,
                glyphSize: 17,
              ),
              title: Text(item.label),
              subtitle: Text(_strategySubtitle(item, l10n), maxLines: 2),
              trailing: Text(
                l10n.logTimes(countOf(item.requests)),
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            );
          },
        ),
      if (snapshot.entries.isEmpty)
        SliverToBoxAdapter(
          child: generateSection(
            title: l10n.logsWinnerProviders,
            items: [
              LogsSectionEmpty(
                glyph: AppGlyphs.shuffle,
                title: l10n.logsNoWinners,
                description: l10n.logsNoWinnersBody,
              ),
            ],
          ),
        )
      else
        ...lazySectionSlivers(
          title: l10n.logsWinnerProviders,
          itemCount: snapshot.entries.length,
          footer: l10n.logsWinnerFooter,
          itemBuilder: (context, index) {
            final entry = snapshot.entries[index];
            // The list is sorted by wins, so the first row is the yardstick for every bar.
            final topWins = snapshot.entries.first.wins;
            return ListItem(
              leading: LogsRankBadge(rank: index + 1),
              title: Text(entry.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    Text(
                      l10n.logsAverageWinLatency(
                        millisOf(entry.averageLatencyMs),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    LogsRowBar(share: topWins <= 0 ? 0 : entry.wins / topWins),
                  ],
                ),
              ),
              trailing: Text(
                l10n.logTimes(countOf(entry.wins)),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .toTabular
                    .copyWith(color: colorScheme.primary),
              ),
            );
          },
        ),
      if (snapshot.smartSelections.isNotEmpty)
        ...lazySectionSlivers(
          title: l10n.logsSmartPrimary,
          itemCount: snapshot.smartSelections.length,
          footer: l10n.logsSmartPrimaryFooter,
          itemBuilder: (context, index) {
            final item = snapshot.smartSelections[index];
            return ListItem(
              leading: IconBadge(
                glyph: AppGlyphs.sparkle,
                color: SurfaceLevel.block.colorOf(colorScheme),
                foregroundColor: colorScheme.primary,
                shape: AppShape.circle,
                size: 34,
                glyphSize: 17,
              ),
              title: Text(item.name),
              subtitle: Text(
                l10n.logsPrimaryHit(
                  percentOf(item.selectedSuccessRate),
                  millisOf(item.averageElapsedMs),
                ),
                maxLines: 2,
              ),
              trailing: Text(
                l10n.logTimes(countOf(item.selectedCount)),
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            );
          },
        ),
    ];
  }

  /// Row subtitle; only smart selection appends primary hit rate and fallbacks.
  static String _strategySubtitle(RaceStrategyDisplay item, AppL10n l10n) {
    final parts = <String>[
      l10n.logsSuccessWith(percentOf(item.successRate)),
      l10n.logsAverageWith(millisOf(item.averageElapsedMs)),
    ];
    if (item.strategy == 'smart_prediction' || item.strategy == 'prediction') {
      parts.add(l10n.logsPrimaryHitOnly(percentOf(item.primaryWinRate)));
      parts.add(l10n.logsFallbackUses(countOf(item.fallbackUses)));
    }
    return parts.join(' · ');
  }

  static Glyph _strategyGlyph(String strategy) => switch (strategy) {
    'smart_prediction' || 'prediction' => AppGlyphs.sparkle,
    'primary_backup' => AppGlyphs.split,
    'single' => AppGlyphs.dns,
    _ => AppGlyphs.shuffle,
  };
}
