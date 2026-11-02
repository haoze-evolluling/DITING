import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The explainer card used by configuration pages: a small glyph and a footnote on the card surface.
///
/// Less loud than [InlineNotice] and more compact than [PageIntroCard]: this one sits between list
/// sections to explain a rule the rows below cannot state themselves.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.text, this.glyph = AppGlyphs.info});

  final String text;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: CommonCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              GlyphIcon(glyph, size: 18, color: colorScheme.onSurfaceVariant),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      borderRadius: AppRadius.full,
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
