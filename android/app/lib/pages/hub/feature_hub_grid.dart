import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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
  final IconData glyph;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  final String? hint;
}

class FeatureHubCategoryData {
  const FeatureHubCategoryData({required this.title, required this.cards});

  final String title;
  final List<FeatureHubCardData> cards;
}

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

  static const _cardHeight = 92.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [for (var i = 0; i < cards.length; i += 2) _row(i)],
    );
  }

  Widget _row(int index) {
    final left = cards[index];
    final right = index + 1 < cards.length ? cards[index + 1] : null;
    return Padding(
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
              shape: AppShape.standard,
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
                    Icon(card.glyph, size: 20, color: colorScheme.primary),
                    const Spacer(),
                    if (card.hint != null)
                      Text(
                        card.hint!,
                        style: AppTextRole.micro
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
                Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextRole.bodyStrong
                      .of(context)
                      .copyWith(color: colorScheme.onSurface),
                ),
                Text(
                  card.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextRole.micro
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
