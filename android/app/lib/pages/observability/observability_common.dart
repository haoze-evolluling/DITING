/// Shared by the four observability pages so byte, rate and duration units cannot diverge.
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

/// Rate text, e.g. `82.4 KB/s`. Below 1 KB it shows whole bytes, never `0.0 KB/s`.
String obsFormatSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1000) {
    return '$bytesPerSecond B/s';
  }
  return '${obsFormatBytes(bytesPerSecond)}/s';
}

/// Duration text: `42 s`, `12 min 4 s`, `1 h 8 min`.
String obsFormatDuration(int seconds, AppL10n l10n) {
  if (seconds < 60) {
    return l10n.durationSeconds(seconds);
  }
  if (seconds < 3600) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0
        ? l10n.durationMinutes(minutes)
        : '${l10n.durationMinutes(minutes)} ${l10n.durationSeconds(rest)}';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return minutes == 0
      ? l10n.durationHours(hours)
      : '${l10n.durationHours(hours)} ${l10n.durationMinutes(minutes)}';
}

/// Latency text, from `0 ms` (cache hit) to `2000 ms` (timeout).
String obsFormatLatency(int milliseconds, AppL10n l10n) =>
    milliseconds == 0 ? l10n.obsCacheHit : '$milliseconds ms';

/// Confirmation dialog returning whether the user confirmed; the action label comes from
/// the caller, cancel always uses UiLocalizations.
Future<bool> showObsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final localizations = UiLocalizations.of(context);
  final confirmed = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: title,
      destructive: destructive,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message),
    ),
  );
  return confirmed == true;
}

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

/// Node to policy group chain. The chip is not tappable because the chain is information
/// only, and a tappable style would promise an expansion that does not exist.
class ObsChainTrail extends StatelessWidget {
  const ObsChainTrail({super.key, required this.chains});

  final List<String> chains;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, chain) in chains.indexed) ...[
          if (index > 0)
            GlyphIcon(
              AppGlyphs.chevronForward,
              size: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          TonalChip(
            label: chain,
            color: context.raisedSurfaceLevel.colorOf(colorScheme),
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );
  }
}

/// One chain step: dot, vertical line, node name, role. The line uses Stack and Positioned
/// rather than IntrinsicHeight plus Expanded, which would measure every row.
class ChainStepRow extends StatelessWidget {
  const ChainStepRow({
    super.key,
    required this.label,
    required this.detail,
    required this.isLast,
  });

  final String label;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          if (!isLast)
            Positioned(
              left: 2.75,
              top: 13,
              bottom: 0,
              child: SizedBox(
                width: 1.5,
                child: ColoredBox(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: isLast
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    shape: AppShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 7),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 2, bottom: isLast ? 8 : 14),
                  child: Row(
                    spacing: 8,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.subheadline
                              .of(context)
                              .copyWith(
                                color: isLast
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Text(
                        detail,
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
