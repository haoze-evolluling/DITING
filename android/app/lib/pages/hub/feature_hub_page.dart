import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/hub/feature_hub_grid.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_android/state/feature_hub_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class FeatureHubPage extends ConsumerWidget {
  const FeatureHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          icon: const Icon(TablerIcons.search),
        ),
      ],
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: context.appBarInset)),
          for (final category in categories)
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
                              : () => _longPress(
                                  context,
                                  ref,
                                  card.longPressRoute!,
                                ),
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

  void _open(BuildContext context, MockFeatureCard card) {
    if (!pushStandalone(context, card.route)) {
      openLocation(context, card.route);
    }
  }

  void _longPress(BuildContext context, WidgetRef ref, String route) {
    ref.read(logLongPressHintProvider.notifier).acknowledge();
    openLocation(context, route);
  }
}
