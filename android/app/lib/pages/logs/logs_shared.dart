library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:material_ui/material_ui.dart';

// dnsTypeName now lives in data/dns_type_name.dart (the aggregate layer needs it
// too); re-exported here so page imports stay unchanged.
export 'package:diting_android/data/dns_type_name.dart' show dnsTypeName;

/// Seconds to `57 min` / `3 h`. Truncates, does not round up.
String remainingLabel(int seconds, AppL10n l10n) {
  if (seconds <= 0) return l10n.logsExpired;
  if (seconds >= 3600) return l10n.durationHours(seconds ~/ 3600);
  if (seconds >= 60) return l10n.durationMinutes(seconds ~/ 60);
  return l10n.durationSeconds(seconds);
}

/// Millisecond timestamp to `MM-dd HH:mm:ss`. Hand-formatted rather than pulling in intl
/// for the single place that needs it.
String shortDateTimeOf(int milliseconds) {
  if (milliseconds <= 0) return currentL10n.obsNone;
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Millisecond timestamp to `HH:mm:ss`.
String clockOf(int milliseconds) {
  if (milliseconds <= 0) return currentL10n.obsNone;
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String countOf(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Percent text: `12.3%`, no trailing `.0`.
String percentOf(double ratio) {
  final rounded = (ratio.clamp(0.0, 1.0) * 1000).round() / 10;
  return rounded % 1 == 0 ? '${rounded.toInt()}%' : '$rounded%';
}

String millisOf(num milliseconds) => '${milliseconds.round()} ms';

/// Full-page description block at the top of a log dashboard. Not a card: upstream draws
/// it as two bare lines, and a card would merge with the first stats card below.
class LogsDashboardHero extends StatelessWidget {
  const LogsDashboardHero({
    super.key,
    required this.title,
    required this.description,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  final String title;
  final String description;

  /// Inside the card column the column already supplies the side gutter.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Text(title, style: AppTextStyle.title2.of(context, emphasized: true)),
          Text(
            description,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class LogsPageLoading extends StatelessWidget {
  const LogsPageLoading({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          const CommonCircleLoading.page(),
          Text(
            label,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Empty state shared by the log drill-down pages. Returns [NullStatus] rather than a
/// wrapper widget because NullStatusSwitcher builds the illustration and action itself.
NullStatus logsEmpty({
  required String label,
  String? description,
  Widget? action,
  NullStatusIllustration illustration = NullStatusIllustration.logs,
}) => NullStatus(
  label: label,
  description: description,
  action: action,
  illustration: illustration,
);

/// Three-option time range selector used by the race, bootstrap and subscription pages.
/// Carries no horizontal padding: callers place it in generateSection, which already pads 16.
class LogStatsRangeSelector<T> extends StatelessWidget {
  const LogStatsRangeSelector({
    super.key,
    required this.values,
    required this.labelOf,
    required this.value,
    required this.onChanged,
  });

  final List<T> values;
  final String Function(T value) labelOf;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ChipRow(
      children: [
        for (final option in values)
          FilterPill(
            label: labelOf(option),
            selected: option == value,
            onPressed: () => onChanged(option),
          ),
      ],
    );
  }
}
