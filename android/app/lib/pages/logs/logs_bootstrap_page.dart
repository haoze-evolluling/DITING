import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/logs/logs_overview_card.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/log_refresh_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Bootstrap DNS stats from the real `bootstrap_log` table, one row per probe.
class LogsBootstrapPage extends ConsumerStatefulWidget {
  const LogsBootstrapPage({super.key});

  @override
  ConsumerState<LogsBootstrapPage> createState() => _LogsBootstrapPageState();
}

class _LogsBootstrapPageState extends ConsumerState<LogsBootstrapPage>
    with PageVisibilityMixin<LogsBootstrapPage> {
  /// Probes land here continuously while the tunnel resolves; follow them without a tap.
  LogLiveRefreshNotifier? _logRefresh;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _logRefresh = ref.read(logLiveRefreshProvider.notifier);
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    if (visible == _polling) return;
    _polling = visible;
    if (visible) {
      _logRefresh?.attachPolling();
    } else {
      _logRefresh?.detachPolling();
    }
  }

  @override
  void dispose() {
    if (_polling) _logRefresh?.detachPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncStats = ref.watch(bootstrapStatsProvider);
    final range = ref.watch(bootstrapStatsRangeProvider);
    return CommonScaffold(
      title: context.l10n.logsBootstrapTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.logsRefresh,
          onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.logsTimeRange,
            items: [
              LogStatsRangeSelector<LogStatsRange>(
                values: LogStatsRange.values,
                labelOf: (option) => option.label(context.l10n),
                value: range,
                onChanged: (value) => ref
                    .read(bootstrapStatsRangeProvider.notifier)
                    .select(value),
              ),
            ],
          ),
          _buildStats(context, asyncStats, range),
          ListFooter(text: context.l10n.logsBootstrapFooter),
        ],
      ),
    );
  }

  Widget _buildStats(
    BuildContext context,
    AsyncValue<BootstrapStatsSnapshot> asyncStats,
    LogStatsRange range,
  ) {
    if (!asyncStats.hasValue) {
      if (asyncStats.hasError) {
        return generateSection(
          title: context.l10n.logsOverview,
          items: [
            ListItem(
              leading: const GlyphIcon(AppGlyphs.error),
              title: Text(context.l10n.logsBootstrapLoadFailed),
              subtitle: Text('${asyncStats.error}'),
            ),
          ],
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: LogsPageLoading(label: context.l10n.logsLoadingBootstrap),
      );
    }
    final snapshot = asyncStats.requireValue;
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final hasData = snapshot.attempts > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        generateSection(
          title: l10n.logsOverview,
          footer: hasData
              ? l10n.logsBootstrapSummary(
                  range.label(l10n),
                  countOf(snapshot.attempts),
                )
              : l10n.logsBootstrapEmptyRange,
          items: [
            LogsOverviewCard(
              tiles: [
                LogsOverviewTile(
                  label: l10n.logsAttempts,
                  value: countOf(snapshot.attempts),
                  glyph: AppGlyphs.dns,
                  color: colorScheme.primary,
                ),
                LogsOverviewTile(
                  label: l10n.logsSuccess,
                  value: hasData ? countOf(snapshot.successes) : '—',
                  glyph: AppGlyphs.check,
                  color: hasData
                      ? colorScheme.success
                      : colorScheme.onSurfaceVariant,
                ),
                LogsOverviewTile(
                  label: l10n.commonFailed,
                  value: hasData ? countOf(snapshot.failures) : '—',
                  glyph: AppGlyphs.close,
                  color: hasData && snapshot.failures > 0
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
                LogsOverviewTile(
                  label: l10n.logsAverageElapsed,
                  value: hasData ? millisOf(snapshot.averageElapsedMs) : '—',
                  glyph: AppGlyphs.speed,
                ),
              ],
              ratio: hasData
                  ? LogsRatioBar(
                      label: l10n.logsSuccessRate,
                      value: percentOf(snapshot.successRate),
                      segments: [
                        (value: snapshot.successes, color: colorScheme.success),
                        (value: snapshot.failures, color: colorScheme.error),
                      ],
                    )
                  : null,
            ),
          ],
        ),
        if (snapshot.ips.isEmpty)
          generateSection(
            title: l10n.logsNodes,
            items: [
              LogsSectionEmpty(
                glyph: AppGlyphs.dns,
                title: l10n.logsNoProbes,
                description: l10n.logsNoProbesBody,
              ),
            ],
          )
        else
          generateSection(
            title: l10n.logsNodes,
            footer: l10n.logsNodesFooter,
            items: [
              for (final ip in snapshot.ips)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.dns),
                  title: Text(ip.name.isEmpty ? ip.id : ip.name),
                  subtitle: Text(
                    l10n.logsBootstrapRow(
                      ip.ip,
                      percentOf(
                        ip.attempts == 0 ? 0 : ip.successes / ip.attempts,
                      ),
                      millisOf(ip.averageElapsedMs ?? 0),
                      ip.failures > 0
                          ? l10n.logsBootstrapFailures(countOf(ip.failures))
                          : '',
                    ),
                    maxLines: 2,
                  ),
                  trailing: Text(
                    l10n.logTimes(countOf(ip.attempts)),
                    style: AppTextStyle.subheadline
                        .of(context, emphasized: true)
                        .toTabular
                        .copyWith(color: colorScheme.primary),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
