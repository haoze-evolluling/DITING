import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/hub/feature_hub_grid.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_android/state/feature_hub_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Feature hub migrated from upstream `FeatureHubScreen.kt`: 7 categories, 28 cards,
/// two-column grid. Only layout and modules are ported; express mode filters the same data
/// through the upstream 18-item gate. The grid widgets live in `feature_hub_grid.dart` so the
/// server-mode feature center can share the same layout.
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
    final showLongPressHint = ref.watch(logLongPressHintProvider);
    return CommonScaffold(
      title: context.l10n.bottomBarFeatureHub,
      actions: [
        IconButton(
          tooltip: context.l10n.searchTitle,
          onPressed: () => context.push('/search'),
          icon: const GlyphIcon(AppGlyphs.search),
        ),
      ],
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: context.appBarInset)),
          for (final category in categories)
            // A box adapter gets no repaint boundary of its own, unlike a list item, so without
            // one every scroll frame re-records every visible card.
            SliverToBoxAdapter(
              child: RepaintBoundary(
                child: FeatureHubCategorySection(
                  category: FeatureHubCategoryData(
                    title: category.title,
                    cards: [
                      for (final card in category.cards)
                        FeatureHubCardData(
                          title: card.title,
                          description: card.description,
                          glyph: glyphByName(card.glyphName),
                          onTap: () => _open(context, card),
                          onLongPress: card.longPressRoute == null
                              ? null
                              : () => _longPress(context, ref, card),
                          hint: card.longPressRoute != null && showLongPressHint
                              ? context.l10n.featureHubLongPress
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: DockSpacer()),
        ],
      ),
    );
  }

  /// Tab pages (logs, traffic, tools, settings) open full screen so the bottom bar stays out of the
  /// way and the title bar offers a back arrow; everything else is a normal push.
  void _open(BuildContext context, MockFeatureCard card) {
    if (pushStandalone(context, card.route)) {
      return;
    }
    openLocation(context, card.route);
  }

  void _longPress(BuildContext context, WidgetRef ref, MockFeatureCard card) {
    final route = card.longPressRoute;
    if (route == null) {
      return;
    }
    ref.read(logLongPressHintProvider.notifier).acknowledge();
    openLocation(context, route);
  }
}
