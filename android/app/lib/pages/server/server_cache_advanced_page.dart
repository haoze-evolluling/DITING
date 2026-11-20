import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerCacheAdvancedPage extends ConsumerWidget {
  const ServerCacheAdvancedPage({super.key});

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
    Future<void> save(ServerCacheConfig next) async {
      try {
        await ref
            .read(serverControllerProvider.notifier)
            .saveConfig(config.copyWith(cache: next));
        if (context.mounted) {
          showAppSnack(context, context.l10n.serverCacheSaved);
        }
      } catch (error) {
        if (context.mounted) showAppSnack(context, error.toString());
      }
    }

    return CommonScaffold(
      title: context.l10n.serverCacheAdvanced,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverCacheAdvancedTtl,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.speed, size: 20),
                title: Text(context.l10n.serverCacheMinTtl),
                subtitle: Text(context.l10n.serverCacheMinTtlBody),
                value: cache.minTtlEnabled,
                onChanged: (value) =>
                    save(cache.copyWith(minTtlEnabled: value)),
              ),
              if (cache.minTtlEnabled)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.arrowUp, size: 20),
                  title: Text(context.l10n.serverCacheMinTtlValue),
                  trailing: _Value(label: '${cache.minTtlSeconds}s'),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCacheMinTtlValue,
                      initial: cache.minTtlSeconds,
                      suffix: 's',
                    );
                    if (value != null) {
                      await save(cache.copyWith(minTtlSeconds: value));
                    }
                  },
                ),
            ],
          ),
          generateSection(
            title: context.l10n.serverCacheFallback,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.sync, size: 20),
                title: Text(context.l10n.serverCacheStale),
                subtitle: Text(context.l10n.serverCacheStaleBody),
                value: cache.staleFallbackEnabled,
                onChanged: (value) =>
                    save(cache.copyWith(staleFallbackEnabled: value)),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.warning, size: 20),
                title: Text(context.l10n.serverCacheNegative),
                value: cache.negativeTtlEnabled,
                onChanged: (value) =>
                    save(cache.copyWith(negativeTtlEnabled: value)),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.serverCachePerformance,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.sparkle, size: 20),
                title: Text(context.l10n.serverCacheOptimistic),
                value: cache.optimistic,
                onChanged: (value) => save(cache.copyWith(optimistic: value)),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.bolt, size: 20),
                title: Text(context.l10n.serverCachePrefetch),
                value: cache.prefetchEnabled,
                onChanged: (value) =>
                    save(cache.copyWith(prefetchEnabled: value)),
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

class _Value extends StatelessWidget {
  const _Value({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyle.footnote
          .of(context)
          .copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontFeatures: appTabularFigures,
          ),
    );
  }
}
