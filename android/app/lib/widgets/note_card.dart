import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A rounded progress bar that reads on both the page and a raised card.
///
/// The default `LinearProgressIndicator` track vanishes against the card fill, so both callers
/// painted the track themselves and both had to clip it to a capsule — one copy each, until now.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, this.value, this.minHeight = 6, this.color});

  /// `null` renders an indeterminate bar.
  final double? value;
  final double minHeight;

  /// Bar colour; the theme's primary when omitted.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRSuperellipse(
      borderRadius: AppRadius.standard,
      child: LinearProgressIndicator(
        value: value,
        minHeight: minHeight,
        backgroundColor: context.raisedSurfaceLevel.colorOf(
          context.colorScheme,
        ),
        color: color,
      ),
    );
  }
}
