import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamAdvancedPage extends ConsumerWidget {
  const ServerUpstreamAdvancedPage({super.key});

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.serverCacheClear,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.serverCacheClearBody),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(serverControllerProvider.notifier).clearCache();
      if (context.mounted) {
        showAppSnack(context, context.l10n.serverCacheCleared);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }

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
              if (cache.staleFallbackEnabled)
                ListItem(
                  leading: const Icon(TablerIcons.hourglass, size: 20),
                  title: Text(context.l10n.serverCacheStaleSeconds),
                  trailing: ServerCacheValue(
                    label: '${cache.staleFallbackSeconds}s',
                  ),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCacheStaleSeconds,
                      initial: cache.staleFallbackSeconds,
                      max: 86400,
                      suffix: 's',
                    );
                    if (value != null) {
                      await saveCache(
                        cache.copyWith(staleFallbackSeconds: value),
                      );
                    }
                  },
                ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.alert_triangle, size: 20),
                title: Text(context.l10n.serverCacheNegative),
                value: cache.negativeTtlEnabled,
                onChanged: (value) =>
                    saveCache(cache.copyWith(negativeTtlEnabled: value)),
              ),
              if (cache.negativeTtlEnabled)
                ListItem(
                  leading: const Icon(TablerIcons.clock, size: 20),
                  title: Text(context.l10n.serverCacheNegativeSeconds),
                  trailing: ServerCacheValue(
                    label: '${cache.negativeTtlSeconds}s',
                  ),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCacheNegativeSeconds,
                      initial: cache.negativeTtlSeconds,
                      max: 86400,
                      suffix: 's',
                    );
                    if (value != null) {
                      await saveCache(
                        cache.copyWith(negativeTtlSeconds: value),
                      );
                    }
                  },
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
              if (cache.prefetchEnabled) ...[
                ListItem(
                  leading: const Icon(TablerIcons.stack_2, size: 20),
                  title: Text(context.l10n.serverCachePrefetchThreshold),
                  trailing: ServerCacheValue(
                    label: '${cache.prefetchThreshold}',
                  ),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCachePrefetchThreshold,
                      initial: cache.prefetchThreshold,
                      max: 100,
                    );
                    if (value != null) {
                      await saveCache(
                        cache.copyWith(prefetchThreshold: value),
                      );
                    }
                  },
                ),
                ListItem(
                  leading: const Icon(TablerIcons.clock, size: 20),
                  title: Text(context.l10n.serverCachePrefetchBefore),
                  trailing: ServerCacheValue(
                    label: '${cache.prefetchBeforeExpiryMs}ms',
                  ),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCachePrefetchBefore,
                      initial: cache.prefetchBeforeExpiryMs,
                      min: 100,
                      max: 60000,
                      suffix: 'ms',
                    );
                    if (value != null) {
                      await saveCache(
                        cache.copyWith(prefetchBeforeExpiryMs: value),
                      );
                    }
                  },
                ),
              ],
            ],
            footer: context.l10n.serverCacheFooter,
          ),
          generateSection(
            title: context.l10n.serverCacheActions,
            items: [
              ListItem(
                leading: Icon(
                  TablerIcons.trash,
                  size: 20,
                  color: context.colorScheme.error,
                ),
                title: Text(context.l10n.serverCacheClear),
                subtitle: Text(context.l10n.serverCacheClearBody),
                onTap: () => _clearCache(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
