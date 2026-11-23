library;

import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.glyph,
    this.color,
    this.foregroundColor,
    this.actions,
  });

  const InfoBanner.error({super.key, required this.message, this.actions})
    : glyph = TablerIcons.alert_circle,
      color = null,
      foregroundColor = null;

  const InfoBanner.warning({super.key, required this.message, this.actions})
    : glyph = TablerIcons.alert_triangle,
      color = null,
      foregroundColor = null;

  final String message;
  final IconData? glyph;

  final Color? color;
  final Color? foregroundColor;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (resolvedColor, resolvedForeground) = switch (glyph) {
      TablerIcons.alert_circle => (colorScheme.error, colorScheme.onError),
      TablerIcons.alert_triangle => (
        colorScheme.warningContainer,
        colorScheme.onWarningContainer,
      ),
      _ => (colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
    };
    final tint = color ?? resolvedColor;
    final Color foreground;
    if (foregroundColor != null) {
      foreground = foregroundColor!;
    } else if (color == null) {
      foreground = resolvedForeground;
    } else {
      foreground = tint.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    }
    final actions = this.actions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: ShapeDecoration(
          shape: AppShape.standard,
          color: tint.withValues(alpha: color == null ? 1 : 0.14),
        ),
        child: Row(
          spacing: 10,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(glyph ?? TablerIcons.info_circle, size: 20, color: foreground),
            Expanded(
              child: Text(
                message,
                style: AppTextRole.body.of(context).copyWith(color: foreground),
              ),
            ),
            if (actions != null)
              Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => InfoBanner.error(message: message);
}
