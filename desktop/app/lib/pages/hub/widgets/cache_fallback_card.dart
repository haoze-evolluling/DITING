/// Weak-network fallback: serve a stale record while the upstreams falter, and the optimistic mode
/// that answers with the old value before refreshing it.
///
/// The old desktop console's `CacheConfigCard.vue` holds these under the TTL form; here they are their
/// own card because three switches and a number do not belong in the same card as the mode picker.
/// The switches save on the spot; the stale window is a draft that saves with its button.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_common.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CacheFallbackCard extends ConsumerStatefulWidget {
  const CacheFallbackCard({super.key});

  @override
  ConsumerState<CacheFallbackCard> createState() => _CacheFallbackCardState();
}

class _CacheFallbackCardState extends ConsumerState<CacheFallbackCard> {
  String _staleSeconds = '';
  bool _invalid = false;

  void _submit(DesktopCacheConfig config) {
    final l10n = context.l10n;
    final seconds = int.tryParse(_staleSeconds);
    if (seconds == null || seconds <= 0) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    unawaited(
      saveCacheSetting(
        context,
        ref,
        config.copyWith(staleFallbackSeconds: seconds),
        l10n.desktopCacheConfigSaved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopCacheConfigProvider);
    final config = state.config;
    if (config != null && _staleSeconds.isEmpty) {
      _staleSeconds = '${config.staleFallbackSeconds}';
    }
    void save(DesktopCacheConfig next) =>
        unawaited(saveCacheSetting(context, ref, next, l10n.desktopCacheConfigSaved));
    return DashboardCard(
      semanticLabel: l10n.desktopCacheFallbackTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.speed,
            title: l10n.desktopCacheFallbackTitle,
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopCacheFallbackBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          if (config == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CommonCircleLoading(size: 20)),
            )
          else ...[
            CacheToggleRow(
              title: l10n.desktopCacheStaleTitle,
              body: l10n.desktopCacheStaleBody,
              value: config.staleFallbackEnabled,
              onChanged: (value) =>
                  save(config.copyWith(staleFallbackEnabled: value)),
            ),
            if (config.staleFallbackEnabled) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    child: TextFormField(
                      initialValue: _staleSeconds,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.desktopCacheStaleSeconds,
                      ),
                      style: AppTextStyle.callout.of(context),
                      onChanged: (value) => _staleSeconds = value,
                    ),
                  ),
                  TonalButton(
                    size: TonalButtonSize.compact,
                    glyph: AppGlyphs.check,
                    label: l10n.commonSave,
                    onPressed: state.saving ? null : () => _submit(config),
                  ),
                ],
              ),
              if (_invalid) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.desktopCacheInvalidNumbers,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: context.colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              CacheToggleRow(
                title: l10n.desktopCacheOptimistic,
                body: l10n.desktopCacheOptimisticBody,
                value: config.optimistic,
                onChanged: (value) =>
                    save(config.copyWith(optimistic: value)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
