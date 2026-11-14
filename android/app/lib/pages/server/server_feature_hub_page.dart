import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/hub/feature_hub_grid.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

/// One entry in the server-mode feature center.
class ServerFeatureCard {
  const ServerFeatureCard({
    required this.title,
    required this.description,
    required this.glyph,
    required this.route,
  });

  final String title;
  final String description;
  final Glyph glyph;
  final String route;
}

class ServerFeatureCategory {
  const ServerFeatureCategory({required this.title, required this.cards});

  final String title;
  final List<ServerFeatureCard> cards;
}

/// Server mode's feature center, mirroring the normal-mode feature hub: one card per functional
/// module, grouped into the same top-level categories. Card order is the reading order; keep the
/// config import/export entry (`备份与迁移`) here so it stays reachable in server mode.
List<ServerFeatureCategory> serverFeatureCategories(AppL10n l10n) => [
  ServerFeatureCategory(
    title: l10n.hubCategoryDns,
    cards: [
      ServerFeatureCard(
        title: l10n.serverUpstreamTitle,
        description: l10n.serverHubUpstreamDescription,
        glyph: AppGlyphs.dns,
        route: ServerPaths.upstream,
      ),
      ServerFeatureCard(
        title: l10n.hubCache,
        description: l10n.serverHubCacheDescription,
        glyph: AppGlyphs.memory,
        route: HubPaths.cache,
      ),
      ServerFeatureCard(
        title: l10n.dns64Title,
        description: l10n.dns64Intro,
        glyph: AppGlyphs.link,
        route: '/network/dns64',
      ),
      ServerFeatureCard(
        title: l10n.lanRateLimitTitle,
        description: l10n.lanRateLimitIntro,
        glyph: AppGlyphs.speed,
        route: '/network/lan-rate-limit',
      ),
    ],
  ),
  ServerFeatureCategory(
    title: l10n.serverHubCategoryRules,
    cards: [
      ServerFeatureCard(
        title: l10n.hubRuleControl,
        description: l10n.hubRuleControlDescription,
        glyph: AppGlyphs.rules,
        route: HubPaths.ruleControl,
      ),
      ServerFeatureCard(
        title: l10n.hubBlocklist,
        description: l10n.hubBlocklistDescription,
        glyph: AppGlyphs.block,
        route: Routes.rulesOf('block'),
      ),
      ServerFeatureCard(
        title: l10n.hubAllowlist,
        description: l10n.hubAllowlistDescription,
        glyph: AppGlyphs.verified,
        route: Routes.rulesOf('allow'),
      ),
      ServerFeatureCard(
        title: l10n.hubRewrite,
        description: l10n.hubRewriteDescription,
        glyph: AppGlyphs.swap,
        route: Routes.rulesOf('rewrite'),
      ),
    ],
  ),
  ServerFeatureCategory(
    title: l10n.serverHubCategoryData,
    cards: [
      ServerFeatureCard(
        title: l10n.transferTitle,
        description: l10n.hubBackupDescription,
        glyph: AppGlyphs.export,
        route: HubPaths.configTransfer,
      ),
      ServerFeatureCard(
        title: l10n.hubDataCleanup,
        description: l10n.hubDataCleanupDescription,
        glyph: AppGlyphs.broom,
        route: HubPaths.dataCleanup,
      ),
      ServerFeatureCard(
        title: l10n.hubTroubleshooting,
        description: l10n.hubTroubleshootingDescription,
        glyph: AppGlyphs.wrench,
        route: HubPaths.troubleshooting,
      ),
      ServerFeatureCard(
        title: l10n.autoUpdateTitle,
        description: l10n.hubAutoUpdateDescription,
        glyph: AppGlyphs.refresh,
        route: HubPaths.autoUpdate,
      ),
    ],
  ),
  ServerFeatureCategory(
    title: l10n.hubCategoryInterface,
    cards: [
      ServerFeatureCard(
        title: l10n.serverModeSettings,
        description: l10n.serverModeSettingsBody,
        glyph: AppGlyphs.settings,
        route: ServerPaths.settings,
      ),
      ServerFeatureCard(
        title: l10n.hubAppearance,
        description: l10n.hubAppearanceDescription,
        glyph: AppGlyphs.palette,
        route: SystemPaths.theme,
      ),
      ServerFeatureCard(
        title: l10n.hubAbout,
        description: l10n.hubAboutDescription,
        glyph: AppGlyphs.info,
        route: Routes.about,
      ),
      ServerFeatureCard(
        title: l10n.hubProviderVisibility,
        description: l10n.hubProviderVisibilityDescription,
        glyph: AppGlyphs.eye,
        route: HubPaths.providerVisibility,
      ),
    ],
  ),
];

/// Server-mode "feature center" tab: a two-column card grid of every module server mode supports,
/// including the upstream editor and mode settings (which no longer have dock tabs of their own).
/// Reuses the same grid widgets as the normal-mode feature hub so both screens stay consistent.
class ServerFeatureHubPage extends StatelessWidget {
  const ServerFeatureHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = serverFeatureCategories(context.l10n);
    return CommonScaffold(
      title: context.l10n.bottomBarFeatureHub,
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
                          glyph: card.glyph,
                          onTap: () => _open(context, card),
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

  void _open(BuildContext context, ServerFeatureCard card) {
    openLocation(context, card.route);
  }
}
