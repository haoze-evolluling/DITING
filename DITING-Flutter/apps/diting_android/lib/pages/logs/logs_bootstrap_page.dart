import 'package:diting_shared/app/l10n/l10n.dart';
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

class _LogsBootstrapPageState extends ConsumerState<LogsBootstrapPage> {
  /// Probes land here continuously while the tunnel resolves; follow them without a tap.
  LogLiveRefreshNotifier? _logRefresh;

  @override
  void initState() {
    super.initState();
    _logRefresh = ref.read(logLiveRefreshProvider.notifier);
    _logRefresh!.attachPolling();
  }

  @override
  void dispose() {
    _logRefresh?.detachPolling();
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
    final colorScheme = context.colorScheme;
    final hasData = snapshot.attempts > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        generateSection(
          title: context.l10n.logsOverview,
          footer: hasData
              ? context.l10n.logsBootstrapSummary(
                  range.label(context.l10n),
                  countOf(snapshot.attempts),
                )
              : context.l10n.logsBootstrapEmptyRange,
          items: [
            StatStrip(
              stats: [
                StatItem(label: context.l10n.logsAttempts, value: countOf(snapshot.attempts)),
                StatItem(
                  label: context.l10n.logsSuccess,
                  value: hasData ? countOf(snapshot.successes) : '—',
                  color: colorScheme.success,
                ),
                StatItem(
                  label: context.l10n.logsSuccessRate,
                  value: hasData ? percentOf(snapshot.successRate) : '—',
                ),
                StatItem(
                  label: context.l10n.logsAverageElapsed,
                  value: hasData ? millisOf(snapshot.averageElapsedMs) : '—',
                ),
              ],
            ),
          ],
        ),
        if (snapshot.ips.isEmpty)
          generateSection(
            title: context.l10n.logsNodes,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.dns),
                title: Text(context.l10n.logsNoProbes),
                subtitle: Text(
                  context.l10n.logsNoProbesBody,
                ),
              ),
            ],
          )
        else
          generateSection(
            title: context.l10n.logsNodes,
            footer: context.l10n.logsNodesFooter,
            items: [
              for (final ip in snapshot.ips)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.dns),
                  title: Text(ip.name.isEmpty ? ip.id : ip.name),
                  subtitle: Text(
                    context.l10n.logsBootstrapRow(
                      ip.ip,
                      percentOf(
                        ip.attempts == 0 ? 0 : ip.successes / ip.attempts,
                      ),
                      millisOf(ip.averageElapsedMs ?? 0),
                      ip.failures > 0
                          ? context.l10n.logsBootstrapFailures(
                              countOf(ip.failures),
                            )
                          : '',
                    ),
                    maxLines: 2,
                  ),
                  trailing: Text(
                    context.l10n.logTimes(countOf(ip.attempts)),
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.primary),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
