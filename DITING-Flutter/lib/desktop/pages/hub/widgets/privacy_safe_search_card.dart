/// Forced safe search: the master switch, the seven providers and the rewrite TTL.
///
/// The old desktop console's `SafeSearchCard.vue` is the blueprint. The switch and each provider save
/// on the spot with only the field they change; the TTL is a draft that saves with its button.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_privacy_models.dart';
import 'package:diting/desktop/data/api/desktop_reputation_providers.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacySafeSearchCard extends ConsumerStatefulWidget {
  const PrivacySafeSearchCard({super.key});

  @override
  ConsumerState<PrivacySafeSearchCard> createState() =>
      _PrivacySafeSearchCardState();
}

class _PrivacySafeSearchCardState
    extends ConsumerState<PrivacySafeSearchCard> {
  final _ttl = TextEditingController();
  DesktopSafeSearchConfig? _adopted;
  bool _dirty = false;
  bool _invalid = false;

  @override
  void dispose() {
    _ttl.dispose();
    super.dispose();
  }

  void _adopt(DesktopSafeSearchConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    if (_dirty) return;
    _ttl.text = '${config.effectiveTtl}';
  }

  Future<void> _save(
    Map<String, Object?> patch, {
    required String success,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopSafeSearchProvider.notifier)
        .save(patch);
    if (!mounted) return;
    if (error == null && patch.containsKey('ttl')) {
      setState(() => _dirty = false);
    }
    showDesktopMessage(
      context,
      error == null ? success : l10n.desktopPrivacySaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopSafeSearchProvider);
    final config = state.config;
    if (config != null) _adopt(config);
    final saving = state.saving;
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
                    _save(
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
                                _save(
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  child: TextFormField(
                    controller: _ttl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.desktopSafeSearchTtl,
                    ),
                    style: AppTextStyle.callout.of(context),
                    onChanged: (_) {
                      if (!_dirty) setState(() => _dirty = true);
                      if (_invalid) setState(() => _invalid = false);
                    },
                  ),
                ),
                FilledButton.tonal(
                  onPressed: saving
                      ? null
                      : () {
                          final ttl = int.tryParse(_ttl.text);
                          if (ttl == null || ttl <= 0) {
                            setState(() => _invalid = true);
                            return;
                          }
                          unawaited(
                            _save(
                              {'ttl': ttl},
                              success: l10n.desktopSafeSearchTtlSaved,
                            ),
                          );
                        },
                  child: Text(l10n.desktopSafeSearchTtlSave),
                ),
              ],
            ),
            if (_invalid) ...[
              const SizedBox(height: 6),
              Text(
                l10n.desktopSafeSearchTtlInvalid,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.error,
                ),
              ),
            ],
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
