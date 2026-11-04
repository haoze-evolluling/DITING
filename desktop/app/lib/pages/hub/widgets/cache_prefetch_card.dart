/// Hot-name prefetching and negative-answer caching: the two switches and the thresholds behind the
/// prefetch.
///
/// The old desktop console's `CacheConfigCard.vue` holds these in the same card as the TTL form; here
/// they are their own card. The switches save on the spot, the two numbers are a draft that saves with
/// the button, and an unparseable number is reported instead of being posted.
library;

import 'dart:async';

import 'package:diting_desktop/widgets/desktop_spacing.dart';
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

class CachePrefetchCard extends ConsumerStatefulWidget {
  const CachePrefetchCard({super.key});

  @override
  ConsumerState<CachePrefetchCard> createState() => _CachePrefetchCardState();
}

class _CachePrefetchCardState extends ConsumerState<CachePrefetchCard> {
  String _threshold = '';
  String _before = '';
  bool _invalid = false;

  void _submit(DesktopCacheConfig config) {
    final l10n = context.l10n;
    final threshold = int.tryParse(_threshold);
    final before = int.tryParse(_before);
    if (threshold == null || threshold <= 0 || before == null || before <= 0) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    unawaited(
      saveCacheSetting(
        context,
        ref,
        config.copyWith(
          prefetchThreshold: threshold,
          prefetchBeforeExpiryMs: before,
        ),
        l10n.desktopCacheConfigSaved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopCacheConfigProvider);
    final config = state.config;
    if (config != null && _threshold.isEmpty) {
      _threshold = '${config.prefetchThreshold}';
      _before = '${config.prefetchBeforeExpiryMs}';
    }
    void save(DesktopCacheConfig next) =>
        unawaited(saveCacheSetting(context, ref, next, l10n.desktopCacheConfigSaved));
    return DashboardCard(
      semanticLabel: l10n.desktopCachePrefetchTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.bolt,
            title: l10n.desktopCachePrefetchTitle,
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
            l10n.desktopCachePrefetchBody,
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
              title: l10n.desktopCacheNegative,
              body: l10n.desktopCacheNegativeBody,
              value: config.negativeTtlEnabled,
              onChanged: (value) =>
                  save(config.copyWith(negativeTtlEnabled: value)),
            ),
            const SizedBox(height: 8),
            CacheToggleRow(
              title: l10n.desktopCachePrefetchTitle,
              body: l10n.desktopCachePrefetchBody,
              value: config.prefetchEnabled,
              onChanged: (value) =>
                  save(config.copyWith(prefetchEnabled: value)),
            ),
            if (config.prefetchEnabled) ...[
              const SizedBox(height: AppGap.field),
              Wrap(
                spacing: AppGap.sm,
                runSpacing: AppGap.field,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    child: TextFormField(
                      initialValue: _threshold,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.desktopCachePrefetchThreshold,
                        helperText: l10n.desktopCachePrefetchThresholdHint,
                        helperMaxLines: 3,
                      ),
                      style: AppTextStyle.callout.of(context),
                      onChanged: (value) => _threshold = value,
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: TextFormField(
                      initialValue: _before,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.desktopCachePrefetchBefore,
                        helperText: l10n.desktopCachePrefetchBeforeHint,
                        helperMaxLines: 3,
                      ),
                      style: AppTextStyle.callout.of(context),
                      onChanged: (value) => _before = value,
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
            ],
          ],
        ],
      ),
    );
  }
}
