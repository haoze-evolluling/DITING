import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerFilterPage extends ConsumerWidget {
  const ServerFilterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverFilterTitle,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final filter = config.filter;
    return CommonScaffold(
      title: context.l10n.serverFilterTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverFilterState,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.list_details, size: 20),
                title: Text(context.l10n.serverFilterEnabled),
                subtitle: Text(context.l10n.serverFilterEnabledBody),
                value: filter.enabled,
                onChanged: (value) => _save(
                  context,
                  ref,
                  config,
                  filter.copyWith(enabled: value),
                ),
              ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.shield, size: 20),
                title: Text(context.l10n.serverFilterResponse),
                subtitle: Text(context.l10n.serverFilterResponseBody),
                value: filter.filterResponse,
                onChanged: (value) => _save(
                  context,
                  ref,
                  config,
                  filter.copyWith(filterResponse: value),
                ),
              ),
              ListItem<String>.options(
                leading: const Icon(TablerIcons.shield, size: 20),
                title: Text(context.l10n.serverFilterBlockMode),
                value: filter.blockMode,
                options: const ['null_ip', 'nxdomain', 'refused'],
                textBuilder: (value) => switch (value) {
                  'nxdomain' => context.l10n.serverBlockNxdomain,
                  'refused' => context.l10n.serverBlockRefused,
                  _ => context.l10n.serverBlockNullIp,
                },
                onChanged: (value) => _save(
                  context,
                  ref,
                  config,
                  filter.copyWith(blockMode: value),
                ),
              ),
            ],
          ),
          if (filter.blockMode == 'null_ip')
            generateSection(
              title: context.l10n.serverBlockAddresses,
              items: [
                ListItem(
                  leading: const Icon(TablerIcons.broadcast, size: 20),
                  title: Text(context.l10n.serverBlockingIPv4),
                  trailing: Text(
                    filter.blockingIPv4,
                    style: AppTextRole.supportingText.of(context),
                  ),
                  onTap: () async {
                    final value = await editServerText(
                      context,
                      title: context.l10n.serverBlockingIPv4,
                      initial: filter.blockingIPv4,
                    );
                    if (value == null || !context.mounted) return;
                    await _save(
                      context,
                      ref,
                      config,
                      filter.copyWith(blockingIPv4: value),
                    );
                  },
                ),
                ListItem(
                  leading: const Icon(TablerIcons.broadcast, size: 20),
                  title: Text(context.l10n.serverBlockingIPv6),
                  trailing: Text(
                    filter.blockingIPv6,
                    style: AppTextRole.supportingText.of(context),
                  ),
                  onTap: () async {
                    final value = await editServerText(
                      context,
                      title: context.l10n.serverBlockingIPv6,
                      initial: filter.blockingIPv6,
                    );
                    if (value == null || !context.mounted) return;
                    await _save(
                      context,
                      ref,
                      config,
                      filter.copyWith(blockingIPv6: value),
                    );
                  },
                ),
              ],
            ),
          generateSection(
            title: context.l10n.serverFilterSource,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.playlist_add, size: 20),
                title: Text(context.l10n.serverCustomRules),
                subtitle: Text(
                  context.l10n.serverFilterCustomCount(
                    filter.customRules.length,
                  ),
                ),
                trailing: const Icon(TablerIcons.chevron_right, size: 18),
                onTap: () => context.push(ServerRoutes.filterRules),
              ),
              ListItem(
                leading: const Icon(TablerIcons.cloud_network, size: 20),
                title: Text(context.l10n.serverSubscriptions),
                subtitle: Text(
                  context.l10n.serverFilterSubscriptionCount(
                    filter.lists.length,
                  ),
                ),
                trailing: const Icon(TablerIcons.chevron_right, size: 18),
                onTap: () => context.push(ServerRoutes.filterSubscriptions),
              ),
              ListItem(
                leading: const Icon(TablerIcons.target, size: 20),
                title: Text(context.l10n.serverFilterTestTitle),
                subtitle: Text(context.l10n.serverFilterTestEntryBody),
                trailing: const Icon(TablerIcons.chevron_right, size: 18),
                onTap: () => context.push(ServerRoutes.filterTest),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
    ServerFilterConfig filter,
  ) async {
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(config.copyWith(filter: filter));
      if (context.mounted) {
        showAppSnack(context, context.l10n.serverFilterSaved);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }
}
