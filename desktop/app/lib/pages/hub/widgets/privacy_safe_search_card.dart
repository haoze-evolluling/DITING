/// Forced safe search: the master switch and the seven providers.
///
/// The old desktop console's `SafeSearchCard.vue` is the blueprint. The switch and each provider save
/// on the spot with only the field they change; the rewrite TTL is a draft and lives beside this card
/// as [PrivacySafeSearchTtlCard], because the provider grid alone already fills a card.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_reputation_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/privacy_common.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacySafeSearchCard extends ConsumerWidget {
  const PrivacySafeSearchCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopSafeSearchProvider);
    final config = state.config;
    final saving = state.saving;
    Future<void> save(
      Map<String, Object?> patch, {
      required String success,
    }) => savePrivacySetting(
      context,
      ref,
      () => ref.read(desktopSafeSearchProvider.notifier).save(patch),
      success,
    );
    return DashboardCard(
      semanticLabel: l10n.desktopSafeSearchTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.search,
            title: l10n.desktopSafeSearchTitle,
            leading: [
              if (config != null)
                DashboardChip(
                  label: config.enabled
                      ? l10n.desktopSafeSearchEnabled(config.enabledCount)
                      : l10n.desktopSafeSearchOff,
                  tone: config.enabled
                      ? DashboardChipTone.ok
                      : DashboardChipTone.idle,
                  dot: config.enabled,
                ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else if (config != null)
                DashboardSwitch(
                  value: config.enabled,
                  semanticLabel: l10n.desktopSafeSearchTitle,
                  onChanged: (value) => unawaited(
                    save(
                      {'enabled': value, 'disabled': config.disabled},
                      success: value
                          ? l10n.desktopSafeSearchOn
                          : l10n.desktopSafeSearchOffMessage,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopSafeSearchBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (config == null)
            _Unavailable(
              loading: state.isLoading,
              onRetry: ref.read(desktopSafeSearchProvider.notifier).reload,
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 520;
                final tiles = [
                  for (final id in desktopSafeSearchServices)
                    _ProviderTile(
                      label: desktopSafeSearchServiceLabel(context, id),
                      selected: config.isServiceEnabled(id),
                      onPressed: saving || !config.enabled
                          ? null
                          : () {
                              final disabled = config.isServiceEnabled(id)
                                  ? [...config.disabled, id]
                                  : [
                                      for (final item in config.disabled)
                                        if (item != id) item,
                                    ];
                              unawaited(
                                save(
                                  {'disabled': disabled},
                                  success: l10n.desktopSafeSearchServiceSaved,
                                ),
                              );
                            },
                    ),
                ];
                if (!twoColumns) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 6,
                    children: tiles,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    for (var index = 0; index < tiles.length; index += 2)
                      Row(
                        spacing: 6,
                        children: [
                          Expanded(child: tiles[index]),
                          Expanded(
                            child: index + 1 < tiles.length
                                ? tiles[index + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              l10n.desktopSafeSearchFooter,
              style: DashboardText.label(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        spacing: 6,
        children: [
          GlyphIcon(
            selected ? AppGlyphs.checkCircle : AppGlyphs.picker,
            size: 16,
            color: selected ? colorScheme.onPrimary : null,
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.callout.of(context, emphasized: true).copyWith(
                color: selected ? colorScheme.onPrimary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String desktopSafeSearchServiceLabel(BuildContext context, String id) {
  final l10n = context.l10n;
  return switch (id) {
    'bing' => l10n.desktopSafeSearchBing,
    'duckduckgo' => l10n.desktopSafeSearchDuckDuckGo,
    'ecosia' => l10n.desktopSafeSearchEcosia,
    'google' => l10n.desktopSafeSearchGoogle,
    'pixabay' => l10n.desktopSafeSearchPixabay,
    'yandex' => l10n.desktopSafeSearchYandex,
    _ => l10n.desktopSafeSearchYoutube,
  };
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CommonCircleLoading(size: 20)),
      );
    }
    return FilledButton.tonal(
      onPressed: onRetry,
      child: Text(l10n.desktopRetry),
    );
  }
}
