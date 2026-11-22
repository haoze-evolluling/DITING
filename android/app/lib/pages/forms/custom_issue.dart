library;

import 'package:diting_shared/app/l10n/l10n.dart';
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

class CustomIssuesBanner extends StatelessWidget {
  const CustomIssuesBanner({super.key, required this.issues, this.title});

  final List<String> issues;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: ShapeDecoration(
          shape: AppShape.standard,
          color: colorScheme.errorContainer,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Row(
              spacing: 8,
              children: [
                Icon(
                  TablerIcons.alert_triangle,
                  size: 20,
                  color: colorScheme.onErrorContainer,
                ),
                Text(
                  title ?? context.l10n.formIssuesTitle,
                  style: AppTextRole.bodyStrong
                      .of(context)
                      .copyWith(color: colorScheme.onErrorContainer),
                ),
              ],
            ),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  '· $issue',
                  style: AppTextRole.supportingText
                      .of(context)
                      .copyWith(color: colorScheme.onErrorContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
