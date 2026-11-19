import 'package:diting_android/pages/hub/feature_hub_grid.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerHubPage extends ConsumerWidget {
  const ServerHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider);
    return CommonScaffold(
      title: context.l10n.serverHubTitle,
      body: PageBody(
        children: [
          if (snapshot.hasError)
            ServerErrorCard(
              message: snapshot.error.toString(),
              onRetry: () =>
                  ref.read(serverControllerProvider.notifier).refresh(),
            ),
          FeatureHubCategorySection(
            category: FeatureHubCategoryData(
              title: context.l10n.serverHubDataPlane,
              cards: [
                FeatureHubCardData(
                  title: context.l10n.serverUpstreamTitle,
                  description: context.l10n.serverUpstreamHubHint,
                  glyph: AppGlyphs.upstream,
                  onTap: () => context.push(ServerRoutes.upstream),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverFilterTitle,
                  description: context.l10n.serverFilterHubHint,
                  glyph: AppGlyphs.rules,
                  onTap: () => context.push(ServerRoutes.filter),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverCacheTitle,
                  description: context.l10n.serverCacheHubHint,
                  glyph: AppGlyphs.database,
                  onTap: () => context.push(ServerRoutes.cache),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverQueryLogTitle,
                  description: context.l10n.serverQueryLogHubHint,
                  glyph: AppGlyphs.logs,
                  onTap: () => context.push(ServerRoutes.queryLog),
                ),
              ],
            ),
          ),
          FeatureHubCategorySection(
            category: FeatureHubCategoryData(
              title: context.l10n.serverHubSystem,
              cards: [
                FeatureHubCardData(
                  title: context.l10n.serverSettingsTitle,
                  description: context.l10n.serverSettingsHubHint,
                  glyph: AppGlyphs.settings,
                  onTap: () => context.push(ServerRoutes.settings),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverAppearance,
                  description: context.l10n.serverAppearanceHint,
                  glyph: AppGlyphs.palette,
                  onTap: () => context.push(SystemPaths.theme),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverAbout,
                  description: context.l10n.serverAboutHint,
                  glyph: AppGlyphs.info,
                  onTap: () => context.push(Routes.about),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
