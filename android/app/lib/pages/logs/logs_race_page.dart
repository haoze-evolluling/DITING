import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_race_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
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
            child: ListFooter(
              text:
                  context.l10n.logsRaceFooter,
            ),
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
    final snapshot = asyncStats.requireValue;
    final summary = snapshot.summary;
    final colorScheme = context.colorScheme;
    final hasData = summary.requests > 0;

    return [
      SliverToBoxAdapter(
        child: generateSection(
          title: context.l10n.logsOverview,
          footer: hasData
              ? context.l10n.logsRaceSummary(
                  range.label(context.l10n),
                  countOf(summary.requests),
                )
              : context.l10n.logsRaceEmptyRange,
          items: [
            StatStrip(
              stats: [
                StatItem(label: context.l10n.logsRaceRequests, value: countOf(summary.requests)),
                StatItem(
                  label: context.l10n.logsSuccess,
                  value: hasData ? countOf(summary.successes) : '—',
                  color: colorScheme.success,
                ),
                StatItem(
                  label: context.l10n.commonFailed,
                  value: hasData ? countOf(summary.failures) : '—',
                  color: hasData && summary.failures > 0
                      ? colorScheme.error
                      : null,
                ),
                StatItem(
                  label: context.l10n.logsAverageElapsed,
                  value: hasData ? millisOf(summary.averageLatencyMs) : '—',
                ),
              ],
            ),
          ],
        ),
      ),
      if (snapshot.strategyStats.isNotEmpty)
        ...lazySectionSlivers(
          title: context.l10n.logsStrategyOverview,
          itemCount: snapshot.strategyStats.length,
          footer:
              context.l10n.logsStrategyFooter,
          itemBuilder: (context, index) {
            final item = snapshot.strategyStats[index];
            return ListItem(
              leading: GlyphIcon(_strategyGlyph(item.strategy), size: 20),
              title: Text(item.label),
              subtitle: Text(
                _strategySubtitle(item, context.l10n),
                maxLines: 2,
              ),
              trailing: Text(
                context.l10n.logTimes(countOf(item.requests)),
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
            title: context.l10n.logsWinnerProviders,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.shuffle),
                title: Text(context.l10n.logsNoWinners),
                subtitle: Text(context.l10n.logsNoWinnersBody),
              ),
            ],
          ),
        )
      else
        ...lazySectionSlivers(
          title: context.l10n.logsWinnerProviders,
          itemCount: snapshot.entries.length,
          footer: context.l10n.logsWinnerFooter,
          itemBuilder: (context, index) {
            final entry = snapshot.entries[index];
            return ListItem(
              leading: SizedBox(
                width: 24,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: AppTextStyle.headline.of(context, emphasized: true),
                ),
              ),
              title: Text(entry.name),
              subtitle: Text(
              context.l10n.logsAverageWinLatency(
                millisOf(entry.averageLatencyMs),
              ),
            ),
              trailing: Text(
                context.l10n.logTimes(countOf(entry.wins)),
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: colorScheme.primary),
              ),
            );
          },
        ),
      if (snapshot.smartSelections.isNotEmpty)
        ...lazySectionSlivers(
          title: context.l10n.logsSmartPrimary,
          itemCount: snapshot.smartSelections.length,
          footer:
              context.l10n.logsSmartPrimaryFooter,
          itemBuilder: (context, index) {
            final item = snapshot.smartSelections[index];
            return ListItem(
              leading: const GlyphIcon(AppGlyphs.sparkle, size: 20),
              title: Text(item.name),
              subtitle: Text(
                context.l10n.logsPrimaryHit(
                  percentOf(item.selectedSuccessRate),
                  millisOf(item.averageElapsedMs),
                ),
                maxLines: 2,
              ),
              trailing: Text(
                context.l10n.logTimes(countOf(item.selectedCount)),
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
