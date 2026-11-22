library;

import 'package:diting_android/data/network/app_insights.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class AppInsightsView extends StatefulWidget {
  const AppInsightsView({super.key, required this.reports, required this.map});

  final List<AppReport> reports;
  final List<AppConnectionGroup> map;

  @override
  State<AppInsightsView> createState() => _AppInsightsViewState();
}

class _AppInsightsViewState extends State<AppInsightsView> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final reports = widget.reports;
    if (reports.isEmpty) return const SizedBox.shrink();

    final wide = MediaQuery.sizeOf(context).width >= 720;
    final labels = [for (final report in reports) report.appLabel];
    final selected = _selected;
    final selectedIndex = (selected != null && selected < labels.length)
        ? selected
        : 0;
    final l10n = context.l10n;
    if (!wide) {
      return Column(
        children: [
          _reportsSection(reports, null, null),
          for (final group in widget.map) _groupSection(group, l10n),
        ],
      );
    }

    final selectedLabel = labels[selectedIndex];
    final groups = [
      for (final group in widget.map)
        if (group.appLabel == selectedLabel) group,
    ];
    return Row(
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
            children: [for (final group in groups) _groupSection(group, l10n)],
          ),
        ),
      ],
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
            leading: const Icon(TablerIcons.list),
            title: Text(l10n.appInsightsNoDomains),
          )
        else
          for (final domain in group.domains)
            ListItem(
              leading: Icon(
                domain.blocked ? TablerIcons.ban : TablerIcons.circle_check,
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
      leading: Icon(TablerIcons.list, color: color),
      title: Text(
        report.appLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l10n.appInsightsStat(
          report.connectionCount,
          report.blockedCount,
          bytes,
        ),
      ),
      trailing: selected
          ? const Icon(TablerIcons.circle_check)
          : (report.hasBlocked
                ? Icon(TablerIcons.ban, color: color)
                : null),
      onTap: onTap,
    );
  }
}

String _bytes(int value) {
  if (value < 1024) return '${value}B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)}KB';
  return '${(value / (1024 * 1024)).toStringAsFixed(1)}MB';
}
