import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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

  static Color _overCard(BuildContext context, Color color, double alpha) =>
      Color.alphaBlend(
        color.withValues(alpha: alpha),
        SurfaceLevel.card.colorOf(context.colorScheme),
      );
}
