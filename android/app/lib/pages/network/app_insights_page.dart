/// U5 / U6 应用洞察：应用报告卡与连接地图，数据来自实时连接快照。
library;

import 'package:diting_android/data/network/app_insights.dart';
import 'package:diting_android/state/app_insights_providers.dart';
import 'package:diting_android/state/flow_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AppInsightsPage extends ConsumerWidget {
  const AppInsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(appReportsProvider);
    final map = ref.watch(connectionMapProvider);
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.appInsightsTitle,
      actions: [
        IconButton(
          tooltip: l10n.flowRefresh,
          onPressed: () =>
              ref.read(flowViewProvider.notifier).refresh(full: true),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.appInsightsIntro),
          if (reports.isEmpty)
            PageIntroCard(text: l10n.appInsightsEmpty)
          else ...[
            generateSection(
              title: l10n.appInsightsReports,
              items: [
                for (final report in reports)
                  _ReportTile(report: report, bytes: _bytes(report.totalBytes)),
              ],
            ),
            for (final group in map)
              generateSection(
                title: group.appLabel,
                items: [
                  if (group.domains.isEmpty)
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.appsList),
                      title: Text(l10n.appInsightsNoDomains),
                    )
                  else
                    for (final domain in group.domains)
                      ListItem(
                        leading: GlyphIcon(
                          domain.blocked
                              ? AppGlyphs.block
                              : AppGlyphs.checkCircle,
                          color: domain.blocked
                              ? context.colorScheme.error
                              : context.colorScheme.success,
                        ),
                        title: Text(
                          domain.domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          l10n.appInsightsStat(
                            domain.connectionCount,
                            domain.blockedCount,
                            _bytes(domain.totalBytes),
                          ),
                        ),
                      ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, required this.bytes});

  final AppReport report;
  final String bytes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = report.hasBlocked
        ? context.colorScheme.error
        : context.colorScheme.success;
    return ListItem(
      leading: GlyphIcon(AppGlyphs.appsList, color: color),
      title: Text(report.appLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        l10n.appInsightsStat(
          report.connectionCount,
          report.blockedCount,
          bytes,
        ),
      ),
      trailing: report.hasBlocked
          ? GlyphIcon(AppGlyphs.block, color: color)
          : null,
    );
  }
}

String _bytes(int value) {
  if (value < 1024) return '${value}B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)}KB';
  return '${(value / (1024 * 1024)).toStringAsFixed(1)}MB';
}
