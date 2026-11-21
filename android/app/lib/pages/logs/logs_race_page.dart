import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/logs/logs_overview_card.dart';
import 'package:diting_android/pages/logs/logs_row_marks.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_race_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/widgets/leading_slot.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
          icon: const Icon(TablerIcons.refresh),
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
                  labelOf: (option) => option.label(context.l10n),
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
            leading: const Icon(TablerIcons.alert_circle),
            title: Text(context.l10n.logsRaceLoadFailed),
            subtitle: Text('${asyncStats.error}'),
          ),
        );
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
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
                  glyph: TablerIcons.arrows_shuffle,
                  color: colorScheme.primary,
                ),
                LogsOverviewTile(
                  label: l10n.logsSuccess,
                  value: hasData ? countOf(summary.successes) : '—',
                  glyph: TablerIcons.check,
                  color: hasData
                      ? colorScheme.success
                      : colorScheme.onSurfaceVariant,
                ),
                LogsOverviewTile(
                  label: l10n.commonFailed,
                  value: hasData ? countOf(summary.failures) : '—',
                  glyph: TablerIcons.x,
                  color: hasData && summary.failures > 0
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
                LogsOverviewTile(
                  label: l10n.logsAverageElapsed,
                  value: hasData ? millisOf(summary.averageLatencyMs) : '—',
                  glyph: TablerIcons.gauge,
                ),
              ],
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
              leading: LeadingSlot(
                child: IconBadge(
                  glyph: _strategyGlyph(item.strategy),
                  color: SurfaceLevel.block.colorOf(colorScheme),
                  foregroundColor: colorScheme.primary,
                  shape: AppShape.standard,
                  size: 34,
                  glyphSize: 17,
                ),
              ),
              title: Text(item.label),
              subtitle: Text(_strategySubtitle(item, l10n), maxLines: 2),
              trailing: Text(
                l10n.logTimes(countOf(item.requests)),
                style: AppTextRole.body
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
                glyph: TablerIcons.arrows_shuffle,
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
            final topWins = snapshot.entries.first.wins;
            return ListItem(
              leading: LeadingSlot(child: LogsRankBadge(rank: index + 1)),
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
                style: AppTextRole.bodyStrong
                    .of(context)
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
              leading: LeadingSlot(
                child: IconBadge(
                  glyph: TablerIcons.sparkles,
                  color: SurfaceLevel.block.colorOf(colorScheme),
                  foregroundColor: colorScheme.primary,
                  shape: AppShape.standard,
                  size: 34,
                  glyphSize: 17,
                ),
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
                style: AppTextRole.body
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            );
          },
        ),
    ];
  }

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

  static IconData _strategyGlyph(String strategy) => switch (strategy) {
    'smart_prediction' || 'prediction' => TablerIcons.sparkles,
    'primary_backup' => TablerIcons.arrows_split,
    'single' => TablerIcons.cloud_upload,
    _ => TablerIcons.arrows_shuffle,
  };
}
