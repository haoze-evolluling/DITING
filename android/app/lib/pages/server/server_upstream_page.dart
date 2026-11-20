import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final ttl = cache.mode == 'limit_max_ttl'
        ? cache.maxTtlSeconds
        : cache.fixedTtlSeconds;

    Future<void> saveCache(ServerCacheConfig next) async {
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
      title: context.l10n.serverUpstreamTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverUpstreamScheduling,
            items: [
              ListItem<String>.options(
                leading: GlyphIcon(serverModeGlyph(upstream.mode), size: 20),
                title: Text(context.l10n.serverUpstreamMode),
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
            title: context.l10n.serverCacheState,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.database, size: 20),
                title: Text(context.l10n.serverCacheEnabled),
                subtitle: Text(context.l10n.serverCacheEnabledBody),
                value: cache.enabled,
                onChanged: (value) => saveCache(cache.copyWith(enabled: value)),
              ),
            ],
          ),
          if (cache.enabled) ...[
            generateSection(
              title: context.l10n.serverCacheCapacity,
              items: [
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.memory, size: 20),
                  title: Text(context.l10n.serverCacheEntries),
                  trailing: _CacheValue(label: '${cache.maxEntries}'),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCacheEntries,
                      initial: cache.maxEntries,
                      max: 200000,
                    );
                    if (value != null) {
                      await saveCache(cache.copyWith(maxEntries: value));
                    }
                  },
                ),
              ],
            ),
            generateSection(
              title: context.l10n.serverCacheTtl,
              items: [
                ListItem<String>.options(
                  leading: const GlyphIcon(AppGlyphs.sliders, size: 20),
                  title: Text(context.l10n.serverCacheMode),
                  value: cache.mode,
                  options: const ['limit_max_ttl', 'fixed'],
                  textBuilder: (value) => value == 'fixed'
                      ? context.l10n.serverCacheFixed
                      : context.l10n.serverCacheLimit,
                  onChanged: (value) => saveCache(cache.copyWith(mode: value)),
                ),
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.clock, size: 20),
                  title: Text(
                    cache.mode == 'limit_max_ttl'
                        ? context.l10n.serverCacheMaxTtl
                        : context.l10n.serverCacheFixedTtl,
                  ),
                  trailing: _CacheValue(label: '${ttl}s'),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: cache.mode == 'limit_max_ttl'
                          ? context.l10n.serverCacheMaxTtl
                          : context.l10n.serverCacheFixedTtl,
                      initial: ttl,
                      suffix: 's',
                    );
                    if (value == null) return;
                    await saveCache(
                      cache.mode == 'limit_max_ttl'
                          ? cache.copyWith(maxTtlSeconds: value)
                          : cache.copyWith(fixedTtlSeconds: value),
                    );
                  },
                ),
              ],
            ),
            generateSection(
              title: context.l10n.serverCacheAdvancedTtl,
              items: [
                ListItem.toggle(
                  leading: const GlyphIcon(AppGlyphs.speed, size: 20),
                  title: Text(context.l10n.serverCacheMinTtl),
                  subtitle: Text(context.l10n.serverCacheMinTtlBody),
                  value: cache.minTtlEnabled,
                  onChanged: (value) =>
                      saveCache(cache.copyWith(minTtlEnabled: value)),
                ),
                if (cache.minTtlEnabled)
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.arrowUp, size: 20),
                    title: Text(context.l10n.serverCacheMinTtlValue),
                    trailing: _CacheValue(label: '${cache.minTtlSeconds}s'),
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
                      saveCache(cache.copyWith(staleFallbackEnabled: value)),
                ),
                ListItem.toggle(
                  leading: const GlyphIcon(AppGlyphs.warning, size: 20),
                  title: Text(context.l10n.serverCacheNegative),
                  value: cache.negativeTtlEnabled,
                  onChanged: (value) =>
                      saveCache(cache.copyWith(negativeTtlEnabled: value)),
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
                  onChanged: (value) =>
                      saveCache(cache.copyWith(optimistic: value)),
                ),
                ListItem.toggle(
                  leading: const GlyphIcon(AppGlyphs.bolt, size: 20),
                  title: Text(context.l10n.serverCachePrefetch),
                  value: cache.prefetchEnabled,
                  onChanged: (value) =>
                      saveCache(cache.copyWith(prefetchEnabled: value)),
                ),
              ],
              footer: context.l10n.serverCacheFooter,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
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

class _CacheValue extends StatelessWidget {
  const _CacheValue({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextRole.supportingText
          .of(context)
          .copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontFeatures: appTabularFigures,
          ),
    );
  }
}
