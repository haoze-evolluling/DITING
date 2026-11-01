/// Small shared pieces of the protection pages: the subscription health badge, the timestamp shape
/// and the counters strip. Nothing here decides blocking state; the service does.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_filter_models.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// `07-14 09:32` — the console's `formatMonthDayTime`, in the host's time zone.
String desktopMonthDayTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

/// Empty before the first pull; the row then shows only the "never updated" text.
String desktopFilterHealthLabel(
  BuildContext context,
  DesktopFilterList list,
) {
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

/// The service's own reason for the last pull; falls back to the badge's explanation.
String desktopFilterHealthDetail(
  BuildContext context,
  DesktopFilterList list,
) {
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

/// One `label : value` block of the counters strip.
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
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 3,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.figure(context, AppTextStyle.headline),
              ),
            ),
            if (unit != null)
              Text(unit, style: DashboardText.unit(context)),
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
