/// Small shared pieces of the protection pages: the subscription health badge, the timestamp shape
/// and the counters strip. Nothing here decides blocking state; the service does.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_filter_models.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
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

/// `1 小时 5 分` — the console's `pauseRemainingText`, rounded down as it does.
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

/// A title, an explanation and a switch: the console's repeated row shape for the protection
/// switches. The surrounding block owns the tap, so a narrow window does not need a pixel-perfect
/// hit on the track.
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

  /// Shown under the row when the switch is on and the choice needs a caution.
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
