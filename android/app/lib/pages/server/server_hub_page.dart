import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/hub/feature_hub_grid.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
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
    final config = snapshot.value?.config ?? const ServerConfig();
    final upstream = config.upstream;
    final filter = config.filter;
    final queryLog = config.queryLog;
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
                  title: context.l10n.serverUpstreamProviders,
                  description: upstream.providers.isEmpty
                      ? context.l10n.serverUpstreamRequired
                      : context.l10n.serverUpstreamShort(
                          upstream.providers.length,
                        ),
                  glyph: AppGlyphs.dns,
                  onTap: () => context.push(ServerRoutes.upstreamProviders),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverUpstreamTitle,
                  description: serverModeLabel(context, upstream.mode),
                  glyph: AppGlyphs.upstream,
                  onTap: () => context.push(ServerRoutes.upstream),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverBootstrapSummary,
                  description: upstream.bootstrap.isEmpty
                      ? context.l10n.serverBootstrapDefault
                      : context.l10n.serverBootstrapServerCount(
                          upstream.bootstrap.length,
                        ),
                  glyph: AppGlyphs.language,
                  onTap: () => context.push(ServerRoutes.upstreamBootstrap),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverFilterTitle,
                  description: context.l10n.serverHubFilterSummary(
                    filter.enabled
                        ? context.l10n.commonEnabled
                        : context.l10n.commonDisabled,
                    filter.lists.length,
                  ),
                  glyph: AppGlyphs.rules,
                  onTap: () => context.push(ServerRoutes.filter),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverQueryLogTitle,
                  description: context.l10n.serverHubLogSummary(
                    queryLog.retentionDays,
                    queryLog.fileEnabled
                        ? context.l10n.serverHubLogFileOn
                        : context.l10n.serverHubLogFileOff,
                  ),
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
                  description: context.l10n.serverHubSettingsSummary(
                    config.listen.root
                        ? context.l10n.serverRootMode
                        : context.l10n.serverNonRootMode,
                  ),
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
