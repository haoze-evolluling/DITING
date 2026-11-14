import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// One card in the feature-hub grid. Both the normal-mode hub and the server-mode feature center
/// build these so the two screens keep the same card layout and press feedback.
class FeatureHubCardData {
  const FeatureHubCardData({
    required this.title,
    required this.description,
    required this.glyph,
    required this.onTap,
    this.onLongPress,
    this.hint,
  });

  final String title;
  final String description;
  final Glyph glyph;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Small caption at the card's top-right (for example "可长按"); null hides it.
  final String? hint;
}

/// A titled group of cards; categories render in the order the caller supplies them.
class FeatureHubCategoryData {
  const FeatureHubCategoryData({required this.title, required this.cards});

  final String title;
  final List<FeatureHubCardData> cards;
}

/// One titled category: heading plus a grid of cards. Shared by the normal-mode feature hub and
/// the server-mode feature center so the three work modes share one visual language.
class FeatureHubCategorySection extends StatelessWidget {
  const FeatureHubCategorySection({super.key, required this.category});

  final FeatureHubCategoryData category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListHeader(title: category.title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CardGrid(cards: category.cards),
          ),
        ],
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards});

  final List<FeatureHubCardData> cards;

  static const _gap = 10.0;

  /// Base card height at text scale 1.0; the tinted icon badge, title and subtitle need a little
  /// more room than a bare icon row. A linear `textScaler` matches `clampTextScale`.
  static const _cardHeight = 104.0;

  /// Phone width keeps two columns; a tablet/desktop window fits three, the same count the
  /// settings-style grids use elsewhere. The column count changes the reserve the scrolling body
  /// lays out, not the card presentation.
  static int _columnsFor(double width) => width >= 560 ? 3 : 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += columns) {
          final row = <Widget>[];
          for (var c = 0; c < columns; c++) {
            final index = i + c;
            row.add(
              Expanded(
                child: index < cards.length
                    ? _FeatureCard(card: cards[index])
                    : const SizedBox.shrink(),
              ),
            );
          }
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: Row(spacing: _gap, children: row),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({required this.card});

  final FeatureHubCardData card;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _pressed = false;

  /// Widens the card height with the text scale; `MediaQuery.textScalerOf` is already
  /// clamped globally, so it is used as is.
  static double _heightScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_CardGrid._cardHeight) /
      _CardGrid._cardHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final card = widget.card;
    return Semantics(
      button: true,
      label: '${card.title}，${card.description}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          card.onTap();
        },
        onLongPress: card.onLongPress,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Container(
            height: _CardGrid._cardHeight * _heightScale(context),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: ShapeDecoration(
              shape: AppShape.md,
              color: SurfaceLevel.card.colorOf(colorScheme),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Tinted icon badge: the same rounded-square language as the settings rows,
                    // so a card reads as an icon tile with a label rather than a bare glyph.
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: AppShape.sm,
                        color: colorScheme.primary.withValues(alpha: 0.12),
                      ),
                      child: SizedBox.square(
                        dimension: 34,
                        child: Center(
                          child: GlyphIcon(
                            card.glyph,
                            size: 19,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (card.hint != null)
                      Text(
                        card.hint!,
                        style: AppTextStyle.caption2
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  card.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
