library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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

String obsFormatLatency(int milliseconds, AppL10n l10n) =>
    milliseconds == 0 ? l10n.obsCacheHit : '$milliseconds ms';

void showObsTip(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

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
            style: AppTextRole.body
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

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
            Text(label, style: AppTextRole.rowTitle.of(context)),
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppTextRole.supportingText
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
