import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/hub/feature_hub_grid.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
import 'package:diting_android/routes/branches.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerHubPage extends ConsumerWidget {
  const ServerHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider);
    final config = snapshot.value?.config ?? const ServerConfig();
    final status = snapshot.value?.status ?? const ServerStatus();
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
          _ServiceBanner(status: status),
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
                  glyph: TablerIcons.server_2,
                  onTap: () => context.push(ServerRoutes.upstreamProviders),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverUpstreamTitle,
                  description: context.l10n.serverHubUpstreamSummary(
                    serverModeLabel(context, upstream.mode),
                    config.cache.enabled
                        ? context.l10n.commonEnabled
                        : context.l10n.commonDisabled,
                  ),
                  glyph: TablerIcons.cloud_upload,
                  onTap: () => context.push(ServerRoutes.upstream),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverBootstrapSummary,
                  description: upstream.bootstrap.isEmpty
                      ? context.l10n.serverBootstrapDefault
                      : context.l10n.serverBootstrapServerCount(
                          upstream.bootstrap.length,
                        ),
                  glyph: TablerIcons.language,
                  onTap: () => context.push(ServerRoutes.upstreamBootstrap),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverSettingsTitle,
                  description: context.l10n.serverHubSettingsSummary(
                    config.listen.root
                        ? context.l10n.serverRootMode
                        : context.l10n.serverNonRootMode,
                  ),
                  glyph: TablerIcons.settings,
                  onTap: () => context.push(ServerRoutes.settings),
                ),
              ],
            ),
          ),
          FeatureHubCategorySection(
            category: FeatureHubCategoryData(
              title: context.l10n.serverHubRules,
              cards: [
                FeatureHubCardData(
                  title: context.l10n.serverFilterTitle,
                  description: context.l10n.serverHubFilterSummary(
                    filter.enabled
                        ? context.l10n.commonEnabled
                        : context.l10n.commonDisabled,
                    filter.lists.length,
                  ),
                  glyph: TablerIcons.list_details,
                  onTap: () => context.push(ServerRoutes.filter),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverHubSubscriptions,
                  description: filter.lists.isEmpty
                      ? context.l10n.serverHubSubscriptionsEmpty
                      : context.l10n.serverHubSubscriptionsSummary(
                          filter.lists.length,
                          filter.lists.where((list) => list.hasError).length,
                        ),
                  glyph: TablerIcons.cloud_network,
                  onTap: () => context.push(ServerRoutes.filterSubscriptions),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverFilterTestTitle,
                  description: context.l10n.serverFilterTestEntryBody,
                  glyph: TablerIcons.target,
                  onTap: () => context.push(ServerRoutes.filterTest),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverQueryLogTitle,
                  description: context.l10n.serverHubLogSummary(
                    queryLog.retentionDays,
                    queryLog.fileEnabled
                        ? context.l10n.serverHubLogFileOn
                        : context.l10n.serverHubLogFileOff,
                  ),
                  glyph: TablerIcons.logs,
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
                  title: context.l10n.serverAppearance,
                  description: context.l10n.serverAppearanceHint,
                  glyph: TablerIcons.palette,
                  onTap: () => context.push(SystemPaths.theme),
                ),
                FeatureHubCardData(
                  title: context.l10n.serverAbout,
                  description: context.l10n.serverAboutHint,
                  glyph: TablerIcons.info_circle,
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

/// 配置中心顶部的服务状态条。
///
/// 只说明 DNS 服务是否在对外监听，并与“配置是否可编辑”分开表达：服务停止时
/// 配置、订阅与测试入口依旧全部可用。
class _ServiceBanner extends StatelessWidget {
  const _ServiceBanner({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final running = status.running;
    final active = status.active && !running;
    final dotColor = running
        ? scheme.success
        : active
        ? scheme.warning
        : status.error != null
        ? scheme.error
        : scheme.onSurfaceVariant;
    final title = running
        ? context.l10n.serverListening
        : status.stopping
        ? context.l10n.stateStopping
        : status.restarting
        ? context.l10n.serverRestarting
        : status.starting
        ? context.l10n.serverStarting
        : context.l10n.serverServiceStopped;
    final body = running
        ? (status.addresses.isEmpty
              ? context.l10n.serverClientHint(status.port)
              : status.addresses.join('  ·  '))
        : context.l10n.serverServiceStoppedHint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: CommonCard(
        onPressed: () => context.go(ServerRoutes.root),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: ShapeDecoration(
                color: dotColor,
                shape: AppShape.standard,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(title, style: AppTextRole.sectionLabel.of(context)),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRole.micro
                        .of(context)
                        .copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: running ? appTabularFigures : null,
                        ),
                  ),
                ],
              ),
            ),
            if (!running)
              Text(
                context.l10n.serverServiceGoStart,
                style: AppTextRole.caption
                    .of(context)
                    .copyWith(color: scheme.primary),
              ),
            const Icon(TablerIcons.chevron_right, size: 17),
          ],
        ),
      ),
    );
  }
}
