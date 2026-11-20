import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Theme-derived accents for the server dashboard.
///
/// The dashboard keeps its data visuals in the selected palette instead of mixing fixed
/// success / warning hues into every card. Semantic status colours stay on status dots and
/// exception labels, where they carry meaning rather than decoration.
abstract final class ServerHomeColors {
  static Color accent(BuildContext context) => context.colorScheme.primary;

  static Color accentWash(BuildContext context) =>
      _overCard(context, accent(context), 0.08);

  static Color accentSubtle(BuildContext context) =>
      _overCard(context, accent(context), 0.045);

  static Color accentMuted(BuildContext context) =>
      _overCard(context, accent(context), 0.42);

  static Color accentStrong(BuildContext context) =>
      _overCard(context, accent(context), 0.82);

  static Color track(BuildContext context) =>
      _overCard(context, context.colorScheme.onSurfaceVariant, 0.09);

  static Color chartBase(BuildContext context) =>
      _overCard(context, accent(context), 0.50);

  static Color chartBlocked(BuildContext context) =>
      _overCard(context, accent(context), 0.92);

  static Color divider(BuildContext context) =>
      context.colorScheme.onSurfaceVariant.withValues(alpha: 0.12);

  static Color mutedInk(BuildContext context) =>
      context.colorScheme.onSurfaceVariant;

  static Color _overCard(BuildContext context, Color color, double alpha) =>
      Color.alphaBlend(
        color.withValues(alpha: alpha),
        SurfaceLevel.card.colorOf(context.colorScheme),
      );
}
