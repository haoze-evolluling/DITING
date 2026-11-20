library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_filter_models.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

String desktopMonthDayTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

String desktopFilterHealthLabel(BuildContext context, DesktopFilterList list) {
  final l10n = context.l10n;
  return switch (list.lastStatus) {
    'ok' => l10n.desktopFilterListHealthOk,
    'unchanged' => l10n.desktopFilterListHealthUnchanged,
    'cached' => l10n.desktopFilterListHealthCached,
    'failed' => l10n.desktopFilterListHealthFailed,
    _ => '',
  };
}

DashboardChipTone desktopFilterHealthTone(DesktopFilterList list) =>
    switch (list.lastStatus) {
      'ok' => DashboardChipTone.ok,
      'unchanged' => DashboardChipTone.idle,
      'cached' || 'failed' => DashboardChipTone.warn,
      _ => DashboardChipTone.idle,
    };

String desktopFilterHealthDetail(BuildContext context, DesktopFilterList list) {
  if (list.lastError.isNotEmpty) return list.lastError;
  final l10n = context.l10n;
  return switch (list.lastStatus) {
    'ok' => l10n.desktopFilterListHealthOkBody,
    'unchanged' => l10n.desktopFilterListHealthUnchangedBody,
    'cached' => l10n.desktopFilterListHealthCachedBody,
    'failed' => l10n.desktopFilterListHealthFailedBody,
    _ => '',
  };
}

String desktopPauseRemaining(BuildContext context, Duration remaining) {
  final l10n = context.l10n;
  final seconds = remaining.inSeconds;
  if (seconds <= 0) return '';
  if (seconds >= 86400) {
    return l10n.desktopFilterPauseDays((seconds / 86400).ceil());
  }
  if (seconds >= 3600) {
    return l10n.desktopFilterPauseHours(
      seconds ~/ 3600,
      (seconds % 3600) ~/ 60,
    );
  }
  if (seconds >= 60) {
    return l10n.desktopFilterPauseMinutes(seconds ~/ 60, seconds % 60);
  }
  return l10n.desktopFilterPauseSeconds(seconds);
}

class FilterMetric extends StatelessWidget {
  const FilterMetric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final unit = this.unit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 3,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.figure(context, AppTextRole.metricCompact),
              ),
            ),
            if (unit != null) Text(unit, style: DashboardText.unit(context)),
          ],
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
      ],
    );
  }
}

class FilterToggleRow extends StatelessWidget {
  const FilterToggleRow({
    super.key,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
    this.warning,
  });

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool>? onChanged;

  final String? warning;

  @override
  Widget build(BuildContext context) {
    final warning = this.warning;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
              ),
              DashboardSwitch(
                value: value,
                semanticLabel: title,
                onChanged: onChanged,
              ),
            ],
          ),
          Text(
            body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (value && warning != null)
            Text(
              warning,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(
                context,
                color: context.colorScheme.warning,
              ),
            ),
        ],
      ),
    );
  }
}
