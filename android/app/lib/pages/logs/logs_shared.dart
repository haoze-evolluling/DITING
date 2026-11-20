library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:material_ui/material_ui.dart';

export 'package:diting_android/data/dns_type_name.dart' show dnsTypeName;

String remainingLabel(int seconds, AppL10n l10n) {
  if (seconds <= 0) return l10n.logsExpired;
  if (seconds >= 3600) return l10n.durationHours(seconds ~/ 3600);
  if (seconds >= 60) return l10n.durationMinutes(seconds ~/ 60);
  return l10n.durationSeconds(seconds);
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String shortDateTimeOf(int milliseconds) {
  if (milliseconds <= 0) return currentL10n.obsNone;
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${_twoDigits(time.month)}-${_twoDigits(time.day)} '
      '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:'
      '${_twoDigits(time.second)}';
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

String percentOf(double ratio) {
  final rounded = (ratio.clamp(0.0, 1.0) * 1000).round() / 10;
  return rounded % 1 == 0 ? '${rounded.toInt()}%' : '$rounded%';
}

String millisOf(num milliseconds) => '${milliseconds.round()} ms';

class LogsDashboardHero extends StatelessWidget {
  const LogsDashboardHero({
    super.key,
    required this.title,
    required this.description,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  final String title;
  final String description;

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
          Text(title, style: AppTextRole.sectionTitle.of(context)),
          Text(
            description,
            style: AppTextRole.body
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
            style: AppTextRole.body
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

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
