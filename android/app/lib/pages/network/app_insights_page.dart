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

class AppInsightsPage extends ConsumerStatefulWidget {
  const AppInsightsPage({super.key});

  @override
  ConsumerState<AppInsightsPage> createState() => _AppInsightsPageState();
}

class _AppInsightsPageState extends ConsumerState<AppInsightsPage> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(appReportsProvider);
    final map = ref.watch(connectionMapProvider);
    final l10n = context.l10n;
    final actions = [
      IconButton(
        tooltip: l10n.flowRefresh,
        onPressed: () => ref.read(flowViewProvider.notifier).refresh(full: true),
        icon: const GlyphIcon(AppGlyphs.refresh),
      ),
    ];
    if (reports.isEmpty) {
      return CommonScaffold(
        title: l10n.appInsightsTitle,
        actions: actions,
        body: PageBody(
          children: [
            PageIntroCard(text: l10n.appInsightsIntro),
            PageIntroCard(text: l10n.appInsightsEmpty),
          ],
        ),
      );
    }

    // U9: on a tablet the report cards become the left pane and the selected app's connection map
    // the right, instead of one long scroll where the map is far from the card that explains it.
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final labels = [for (final report in reports) report.appLabel];
    final selectedIndex = (_selected != null && _selected! < labels.length)
        ? _selected!
        : 0;
    if (!wide) {
      return CommonScaffold(
        title: l10n.appInsightsTitle,
        actions: actions,
        body: PageBody(
          children: [
            PageIntroCard(text: l10n.appInsightsIntro),
            _reportsSection(reports, null, null),
            for (final group in map) _groupSection(group, l10n),
          ],
        ),
      );
    }

    final selectedLabel = labels[selectedIndex];
    final groups = [
      for (final group in map)
        if (group.appLabel == selectedLabel) group,
    ];
    return CommonScaffold(
      title: l10n.appInsightsTitle,
      actions: actions,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.appInsightsIntro),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: _reportsSection(reports, selectedIndex, (index) {
                  setState(() => _selected = index);
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    for (final group in groups) _groupSection(group, l10n),
                    if (groups.isEmpty)
                      PageIntroCard(text: l10n.appInsightsNoDomains),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reportsSection(
    List<AppReport> reports,
    int? selected,
    ValueChanged<int>? onSelect,
  ) {
    return generateSection(
      title: context.l10n.appInsightsReports,
      items: [
        for (final (index, report) in reports.indexed)
          _ReportTile(
            report: report,
            bytes: _bytes(report.totalBytes),
            selected: selected == index,
            onTap: onSelect == null ? null : () => onSelect(index),
          ),
      ],
    );
  }

  Widget _groupSection(AppConnectionGroup group, AppL10n l10n) {
    return generateSection(
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
                domain.blocked ? AppGlyphs.block : AppGlyphs.checkCircle,
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
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.bytes,
    this.selected = false,
    this.onTap,
  });

  final AppReport report;
  final String bytes;
  final bool selected;
  final VoidCallback? onTap;

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
      trailing: selected
          ? const GlyphIcon(AppGlyphs.checkCircle)
          : (report.hasBlocked ? GlyphIcon(AppGlyphs.block, color: color) : null),
      onTap: onTap,
    );
  }
}

String _bytes(int value) {
  if (value < 1024) return '${value}B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)}KB';
  return '${(value / (1024 * 1024)).toStringAsFixed(1)}MB';
}
