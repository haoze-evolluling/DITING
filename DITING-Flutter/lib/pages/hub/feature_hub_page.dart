import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/mock_data.dart';
import 'package:diting/router.dart';
import 'package:diting/routes/standalone_routes.dart';
import 'package:diting/state/feature_hub_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/glyph_lookup.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Feature hub migrated from upstream `FeatureHubScreen.kt`: 7 categories, 28 cards,
/// two-column grid. Only layout and modules are ported; express mode filters the same data
/// through the upstream 18-item gate.
class FeatureHubPage extends ConsumerWidget {
  const FeatureHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Card visibility follows the persisted hidden set (`dns_vpn_prefs` /
    // `hidden_features_set`); filtering lives in the provider so toggling updates immediately.
    // The localized resources come from this context, so a language switch relabels the cards.
    final categories = ref.watch(
      visibleFeatureCategoriesProvider(context.l10n),
    );
    return CommonScaffold(
      title: context.l10n.bottomBarFeatureHub,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: context.appBarInset)),
          for (final category in categories)
            // A box adapter gets no repaint boundary of its own, unlike a list item, so without
            // one every scroll frame re-records every visible card.
            SliverToBoxAdapter(
              child: RepaintBoundary(
                child: _CategorySection(category: category),
              ),
            ),
          const SliverToBoxAdapter(child: DockSpacer()),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category});

  final MockFeatureCategory category;

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

  final List<MockFeatureCard> cards;

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

class _FeatureCard extends ConsumerStatefulWidget {
  const _FeatureCard({required this.card});

  final MockFeatureCard card;

  @override
  ConsumerState<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends ConsumerState<_FeatureCard> {
  bool _pressed = false;

  /// Widens the card height with the text scale; `MediaQuery.textScalerOf` is already
  /// clamped globally, so it is used as is.
  static double _heightScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_CardGrid._cardHeight) /
      _CardGrid._cardHeight;

  /// Tab pages (logs, traffic, tools, settings) open full screen so the bottom bar stays out of the
  /// way and the title bar offers a back arrow; everything else is a normal push.
  void _open() {
    final route = widget.card.route;
    if (pushStandalone(context, route)) {
      return;
    }
    openLocation(context, route);
  }

  void _longPress() {
    final route = widget.card.longPressRoute;
    if (route == null) {
      return;
    }
    ref.read(logLongPressHintProvider.notifier).acknowledge();
    openLocation(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final card = widget.card;
    final showLongPressHint =
        card.longPressRoute != null && ref.watch(logLongPressHintProvider);
    return Semantics(
      button: true,
      label: '${card.title}，${card.description}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _open();
        },
        onLongPress: card.longPressRoute == null ? null : _longPress,
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
                    GlyphIcon(
                      glyphByName(card.glyphName),
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const Spacer(),
                    if (showLongPressHint)
                      Text(
                        context.l10n.featureHubLongPress,
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
