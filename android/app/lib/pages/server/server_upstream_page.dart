import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamPage extends ConsumerWidget {
  const ServerUpstreamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverUpstreamTitle,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final upstream = config.upstream;
    final cache = config.cache;

    Future<void> saveCache(ServerCacheConfig next) =>
        saveServerCache(context, ref, config, next);

    return CommonScaffold(
      title: context.l10n.serverUpstreamTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverUpstreamMode,
            items: [
              ListItem<String>.options(
                leading: Icon(serverModeGlyph(upstream.mode), size: 20),
                title: Text(context.l10n.serverUpstreamScheduling),
                subtitle: Text(serverModeDescription(context, upstream.mode)),
                value: upstream.mode,
                options: serverUpstreamModes,
                textBuilder: (mode) => serverModeLabel(context, mode),
                onChanged: (mode) => _save(
                  context,
                  ref,
                  config.copyWith(upstream: upstream.copyWith(mode: mode)),
                ),
              ),
            ],
            footer: context.l10n.serverUpstreamModeNote,
          ),
          generateSection(
            title: context.l10n.serverCacheTitle,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.database, size: 20),
                title: Text(context.l10n.serverCacheEnabled),
                subtitle: Text(context.l10n.serverCacheEnabledBody),
                value: cache.enabled,
                onChanged: (value) => saveCache(cache.copyWith(enabled: value)),
              ),
              if (cache.enabled)
                ListItem(
                  leading: const Icon(TablerIcons.adjustments, size: 20),
                  title: Text(context.l10n.serverCacheAdvanced),
                  subtitle: Text(_cachePolicySummary(context, cache)),
                  trailing: const Icon(TablerIcons.chevron_right, size: 18),
                  onTap: () => context.push(ServerRoutes.upstreamAdvanced),
                ),
            ],
            footer: cache.enabled ? context.l10n.serverCacheFooter : null,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _cachePolicySummary(BuildContext context, ServerCacheConfig cache) {
    final limitMax = cache.mode == 'limit_max_ttl';
    final ttl = limitMax ? cache.maxTtlSeconds : cache.fixedTtlSeconds;
    final label = limitMax
        ? context.l10n.serverCacheMaxTtl
        : context.l10n.serverCacheFixedTtl;
    return context.l10n.serverCachePolicySummary(
      cache.maxEntries,
      '$label ${ttl}s',
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
  ) async {
    try {
      await ref.read(serverControllerProvider.notifier).saveConfig(config);
      if (context.mounted) {
        showAppSnack(context, context.l10n.serverUpstreamSaved);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }
}
