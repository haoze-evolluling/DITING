import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// One card in the feature-hub grid. Both the normal-mode hub and the server-mode feature center
/// build these so the two screens keep the same two-column layout and press feedback.
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

/// One titled category: heading plus a two-column grid of cards. Shared by the normal-mode feature
/// hub and the server-mode feature center.
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

  /// Base card height at text scale 1.0; it scales with the text because icon, title and
  /// subtitle exceed 92dp by about 6dp at 1.4x. A linear `textScaler` matches `clampTextScale`.
  static const _cardHeight = 92.0;

  @override
  Widget build(BuildContext context) {
    // Two equal columns via Row/Column rather than GridView: a handful of cards, and
    // GridView inside a Column needs shrinkWrap.
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final left = cards[i];
      final right = i + 1 < cards.length ? cards[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: Row(
            spacing: _gap,
            children: [
              Expanded(child: _FeatureCard(card: left)),
              if (right != null)
                Expanded(child: _FeatureCard(card: right))
              else
                const Spacer(),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
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
          scale: _pressed ? 0.90 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Container(
            height: _CardGrid._cardHeight * _heightScale(context),
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              shape: AppShape.md,
              color: SurfaceLevel.card.colorOf(colorScheme),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Row(
                  children: [
                    GlyphIcon(card.glyph, size: 20, color: colorScheme.primary),
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
                Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
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
