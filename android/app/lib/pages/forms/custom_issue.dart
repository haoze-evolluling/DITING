/// Form issue banners (upstream `features/form/custom_issue.dart`).
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// All three severities share the banner structure and differ only in color and glyph.
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
    : glyph = AppGlyphs.error,
      color = null,
      foregroundColor = null;

  const InfoBanner.warning({super.key, required this.message, this.actions})
    : glyph = AppGlyphs.warning,
      color = null,
      foregroundColor = null;

  final String message;
  final Glyph? glyph;

  /// `null` infers the severity from `glyph`.
  final Color? color;
  final Color? foregroundColor;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (resolvedColor, resolvedForeground) = switch (glyph) {
      AppGlyphs.error => (colorScheme.error, colorScheme.onError),
      AppGlyphs.warning => (
        colorScheme.warningContainer,
        colorScheme.onWarningContainer,
      ),
      _ => (colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
    };
    final tint = color ?? resolvedColor;
    final foreground =
        foregroundColor ??
        (color == null
            ? resolvedForeground
            : (tint.computeLuminance() > 0.55 ? Colors.black : Colors.white));
    final actions = this.actions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: ShapeDecoration(
          shape: AppShape.xl,
          color: tint.withValues(alpha: color == null ? 1 : 0.14),
        ),
        child: Row(
          spacing: 10,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlyphIcon(glyph ?? AppGlyphs.info, size: 20, color: foreground),
            Expanded(
              child: Text(
                message,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: foreground),
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

/// Error bar: a shorter alias for `InfoBanner.error`.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => InfoBanner.error(message: message);
}

/// Per-row hints live on `FormRow.invalid`; a submit finding four fields needs one place.
class CustomIssuesBanner extends StatelessWidget {
  const CustomIssuesBanner({
    super.key,
    required this.issues,
    this.title,
  });

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
          shape: AppShape.xl,
          color: colorScheme.errorContainer,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Row(
              spacing: 8,
              children: [
                GlyphIcon(
                  AppGlyphs.warning,
                  size: 20,
                  color: colorScheme.onErrorContainer,
                ),
                Text(
                  title ?? context.l10n.formIssuesTitle,
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onErrorContainer),
                ),
              ],
            ),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  '· $issue',
                  style: AppTextStyle.footnote
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
