/// Shared by the observability and traffic pages so byte and latency units cannot diverge.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Bytes as B / KB / MB / GB, base 1000 to match the traffic page.
String obsFormatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Latency text, from `0 ms` (cache hit) to `2000 ms` (timeout).
String obsFormatLatency(int milliseconds, AppL10n l10n) =>
    milliseconds == 0 ? l10n.obsCacheHit : '$milliseconds ms';

/// Bottom tip bar. Operations here do not need a dialog.
void showObsTip(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

/// First-load placeholder: a spinner, not fake `SkeletonText` rows, whose fixed widths make
/// the list jump.
class ObservabilityLoading extends StatelessWidget {
  const ObservabilityLoading({super.key, required this.label});

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

/// Empty state: illustration, text and an optional action. Returns [NullStatus] because
/// NullStatusSwitcher takes NullStatus? directly.
NullStatus obsEmpty({
  required String label,
  required NullStatusIllustration illustration,
  String? description,
  Widget? action,
}) => NullStatus(
  label: label,
  description: description,
  illustration: illustration,
  action: action,
);

/// Read-failure state with retry. The failure is recoverable, so a retry button beats
/// turning the page into an error page.
class ObsFailure extends StatelessWidget {
  const ObsFailure({
    super.key,
    required this.label,
    required this.description,
    required this.onRetry,
  });

  final String label;
  final String description;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            GlyphIcon(AppGlyphs.error, size: 30, color: colorScheme.error),
            Text(label, style: context.listTitleStyle),
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.obsRetry),
            ),
          ],
        ),
      ),
    );
  }
}
