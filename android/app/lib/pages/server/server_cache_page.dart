import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerCachePage extends ConsumerWidget {
  const ServerCachePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverCacheTitle,
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

    final ttl = cache.mode == 'limit_max_ttl'
        ? cache.maxTtlSeconds
        : cache.fixedTtlSeconds;
    return CommonScaffold(
      title: context.l10n.serverCacheTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverCacheState,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.database, size: 20),
                title: Text(context.l10n.serverCacheEnabled),
                subtitle: Text(context.l10n.serverCacheEnabledBody),
                value: cache.enabled,
                onChanged: (value) => save(cache.copyWith(enabled: value)),
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
                  trailing: _Value(label: '${cache.maxEntries}'),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.serverCacheEntries,
                      initial: cache.maxEntries,
                      max: 200000,
                    );
                    if (value != null) {
                      await save(cache.copyWith(maxEntries: value));
                    }
                  },
                ),
              ],
            ),
            ListHeader(title: context.l10n.serverCacheMode),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedControl<String>(
                segments: [
                  ('limit_max_ttl', context.l10n.serverCacheLimit),
                  ('fixed', context.l10n.serverCacheFixed),
                ],
                value: cache.mode,
                onChanged: (value) => save(cache.copyWith(mode: value)),
              ),
            ),
            generateSection(
              title: context.l10n.serverCacheTtl,
              items: [
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.clock, size: 20),
                  title: Text(
                    cache.mode == 'limit_max_ttl'
                        ? context.l10n.serverCacheMaxTtl
                        : context.l10n.serverCacheFixedTtl,
                  ),
                  trailing: _Value(label: '${ttl}s'),
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
                    await save(
                      cache.mode == 'limit_max_ttl'
                          ? cache.copyWith(maxTtlSeconds: value)
                          : cache.copyWith(fixedTtlSeconds: value),
                    );
                  },
                ),
              ],
            ),
            generateSection(
              title: context.l10n.serverCacheBehavior,
              items: [
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.settings, size: 20),
                  title: Text(context.l10n.serverCacheAdvanced),
                  subtitle: Text(context.l10n.serverCacheAdvancedSummary),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                  onTap: () => context.push(ServerRoutes.cacheAdvanced),
                ),
              ],
            ),
          ],
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
