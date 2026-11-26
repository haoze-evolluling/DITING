import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamAdvancedPage extends ConsumerWidget {
  const ServerUpstreamAdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverCacheAdvanced,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final cache = config.cache;

    Future<void> saveCache(ServerCacheConfig next) =>
        saveServerCache(context, ref, config, next);

    return CommonScaffold(
      title: context.l10n.serverCacheAdvanced,
      body: PageBody(
        children: [
          generateSection(
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.gauge, size: 20),
                title: Text(context.l10n.serverCacheMinTtl),
                subtitle: Text(context.l10n.serverCacheMinTtlBody),
                value: cache.minTtlEnabled,
                onChanged: (value) =>
                    saveCache(cache.copyWith(minTtlEnabled: value)),
              ),
              if (cache.minTtlEnabled)
                ListItem(
                  leading: const Icon(TablerIcons.arrow_up, size: 20),
                  title: Text(context.l10n.serverCacheMinTtlValue),
                  trailing: ServerCacheValue(label: '${cache.minTtlSeconds}s'),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCacheMinTtlValue,
                      initial: cache.minTtlSeconds,
                      suffix: 's',
                    );
                    if (value != null) {
                      await saveCache(cache.copyWith(minTtlSeconds: value));
                    }
                  },
                ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.rotate_clockwise, size: 20),
                title: Text(context.l10n.serverCacheStale),
                subtitle: Text(context.l10n.serverCacheStaleBody),
                value: cache.staleFallbackEnabled,
                onChanged: (value) =>
                    saveCache(cache.copyWith(staleFallbackEnabled: value)),
              ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.alert_triangle, size: 20),
                title: Text(context.l10n.serverCacheNegative),
                value: cache.negativeTtlEnabled,
                onChanged: (value) =>
                    saveCache(cache.copyWith(negativeTtlEnabled: value)),
              ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.sparkles, size: 20),
                title: Text(context.l10n.serverCacheOptimistic),
                value: cache.optimistic,
                onChanged: (value) =>
                    saveCache(cache.copyWith(optimistic: value)),
              ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.bolt, size: 20),
                title: Text(context.l10n.serverCachePrefetch),
                value: cache.prefetchEnabled,
                onChanged: (value) =>
                    saveCache(cache.copyWith(prefetchEnabled: value)),
              ),
            ],
            footer: context.l10n.serverCacheFooter,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
