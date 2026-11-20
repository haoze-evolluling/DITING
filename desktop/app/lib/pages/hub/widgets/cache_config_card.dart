library;

import 'dart:async';

import 'package:diting_desktop/widgets/desktop_spacing.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_common.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _numberWidth = 190;

class CacheConfigCard extends ConsumerStatefulWidget {
  const CacheConfigCard({super.key});

  @override
  ConsumerState<CacheConfigCard> createState() => _CacheConfigCardState();
}

class _CacheConfigCardState extends ConsumerState<CacheConfigCard> {
  String _maxTtl = '';
  String _minTtl = '';
  bool _invalid = false;

  void _submit(DesktopCacheConfig config) {
    final l10n = context.l10n;
    final maxTtl = int.tryParse(_maxTtl);
    final minTtl = int.tryParse(_minTtl);
    if (maxTtl == null || maxTtl <= 0 || minTtl == null || minTtl <= 0) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    unawaited(
      saveCacheSetting(
        context,
        ref,
        config.copyWith(maxTtlSeconds: maxTtl, minTtlSeconds: minTtl),
        l10n.desktopCacheConfigSaved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopCacheConfigProvider);
    final config = state.config;
    if (config != null && _maxTtl.isEmpty) {
      _maxTtl = '${config.maxTtlSeconds}';
      _minTtl = '${config.minTtlSeconds}';
    }
    return DashboardCard(
      semanticLabel: l10n.desktopCacheConfigTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sliders,
            title: l10n.desktopCacheConfigTitle,
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.check,
                  tooltip: l10n.desktopCacheConfigSave,
                  onPressed: config == null ? null : () => _submit(config),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (config == null)
            _Unavailable(
              isLoading: state.isLoading,
              error: state.error,
              onRetry: ref.read(desktopCacheConfigProvider.notifier).reload,
            )
          else ...[
            Text(
              l10n.desktopCacheConfigBody,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.desktopCacheModeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DesktopPicker(
                glyph: AppGlyphs.sliders,
                semanticLabel: l10n.desktopCacheModeLabel,
                label: desktopCacheModeLabel(context, config.mode),
                active: true,
                items: [
                  for (final mode in desktopCacheModes)
                    CommonPopupMenuItem(
                      label: desktopCacheModeLabel(context, mode),
                      checked: mode == config.mode,
                      onPressed: () => unawaited(
                        saveCacheSetting(
                          context,
                          ref,
                          config.copyWith(mode: mode),
                          l10n.desktopCacheConfigSaved,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppGap.field),
            Wrap(
              spacing: AppGap.sm,
              runSpacing: AppGap.field,
              children: [
                _NumberField(
                  label: l10n.desktopCacheMaxTtl,
                  value: _maxTtl,
                  onChanged: (value) => _maxTtl = value,
                ),
                _NumberField(
                  label: l10n.desktopCacheMinTtl,
                  value: _minTtl,
                  onChanged: (value) => _minTtl = value,
                ),
              ],
            ),
            if (_invalid) ...[
              const SizedBox(height: 8),
              Text(
                l10n.desktopCacheInvalidNumbers,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.caption
                    .of(context)
                    .copyWith(color: context.colorScheme.error),
              ),
            ],
            if (state.error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                l10n.desktopCacheSaveFailed(error.message),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.caption
                    .of(context)
                    .copyWith(color: context.colorScheme.error),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _numberWidth,
      child: TextFormField(
        initialValue: value,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        style: AppTextRole.body.of(context),
        onChanged: onChanged,
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final bool isLoading;
  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CommonCircleLoading(size: 22)),
      );
    }
    return Row(
      spacing: 8,
      children: [
        GlyphIcon(
          AppGlyphs.warning,
          size: 18,
          color: context.colorScheme.warning,
        ),
        Expanded(
          child: Text(
            error == null
                ? l10n.desktopCacheLoadFailed
                : '${l10n.desktopCacheLoadFailed} · ${error!.message}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.rowTitle(context),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l10n.desktopRetry)),
      ],
    );
  }
}
