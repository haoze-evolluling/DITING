/// The cache policy form: TTL mode, the two lifetime bounds, stale fallback, negative answers and
/// prefetch.
///
/// The old desktop console's `CacheConfigCard.vue` is the blueprint. The switches and the mode
/// travel with the save button, exactly like the console; a rejected save keeps the form and says
/// why, because the service clamps and the page must not pretend it did not.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_common.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Wide enough for `86400` and its label; two of them share a row in a desktop window.
const double _numberWidth = 190;

class CacheConfigCard extends ConsumerStatefulWidget {
  const CacheConfigCard({super.key});

  @override
  ConsumerState<CacheConfigCard> createState() => _CacheConfigCardState();
}

class _CacheConfigCardState extends ConsumerState<CacheConfigCard> {
  /// The numbers as typed. Empty until the first answer arrives, which is what tells the form it
  /// has values to show; a later poll must not overwrite what is being typed.
  String _maxTtl = '';
  String _minTtl = '';
  String _staleSeconds = '';
  String _prefetchThreshold = '';
  String _prefetchBefore = '';
  bool _invalid = false;

  Future<void> _save(DesktopCacheConfig next) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopCacheConfigProvider.notifier)
        .save(next);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopCacheConfigSaved
          : l10n.desktopCacheSaveFailed(error.message),
    );
  }

  /// The button's job: the typed numbers, or a note that they are not usable. The switches save on
  /// the spot through the same provider, so a rejection there flips them back on its own.
  void _submit(DesktopCacheConfig config) {
    final maxTtl = int.tryParse(_maxTtl);
    final minTtl = int.tryParse(_minTtl);
    final staleSeconds = int.tryParse(_staleSeconds);
    final threshold = int.tryParse(_prefetchThreshold);
    final before = int.tryParse(_prefetchBefore);
    final valid =
        maxTtl != null &&
        maxTtl > 0 &&
        minTtl != null &&
        minTtl > 0 &&
        staleSeconds != null &&
        staleSeconds > 0 &&
        threshold != null &&
        threshold > 0 &&
        before != null &&
        before > 0;
    if (!valid) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    unawaited(
      _save(
        config.copyWith(
          maxTtlSeconds: maxTtl,
          minTtlSeconds: minTtl,
          staleFallbackSeconds: staleSeconds,
          prefetchThreshold: threshold,
          prefetchBeforeExpiryMs: before,
        ),
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
      _staleSeconds = '${config.staleFallbackSeconds}';
      _prefetchThreshold = '${config.prefetchThreshold}';
      _prefetchBefore = '${config.prefetchBeforeExpiryMs}';
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
          else
            _form(context, config, state.error),
        ],
      ),
    );
  }

  Widget _form(
    BuildContext context,
    DesktopCacheConfig config,
    DesktopApiException? error,
  ) {
    final l10n = context.l10n;
    void save(DesktopCacheConfig next) => unawaited(_save(next));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          l10n.desktopCacheConfigBody,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        Text(
          l10n.desktopCacheModeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
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
                  onPressed: () => save(config.copyWith(mode: mode)),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
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
        CacheToggleRow(
          title: l10n.desktopCacheStaleTitle,
          body: l10n.desktopCacheStaleBody,
          value: config.staleFallbackEnabled,
          onChanged: (value) =>
              save(config.copyWith(staleFallbackEnabled: value)),
        ),
        if (config.staleFallbackEnabled) ...[
          _NumberField(
            label: l10n.desktopCacheStaleSeconds,
            value: _staleSeconds,
            onChanged: (value) => _staleSeconds = value,
          ),
          CacheToggleRow(
            title: l10n.desktopCacheOptimistic,
            body: l10n.desktopCacheOptimisticBody,
            value: config.optimistic,
            onChanged: (value) => save(config.copyWith(optimistic: value)),
          ),
        ],
        CacheToggleRow(
          title: l10n.desktopCacheNegative,
          body: l10n.desktopCacheNegativeBody,
          value: config.negativeTtlEnabled,
          onChanged: (value) =>
              save(config.copyWith(negativeTtlEnabled: value)),
        ),
        CacheToggleRow(
          title: l10n.desktopCachePrefetchTitle,
          body: l10n.desktopCachePrefetchBody,
          value: config.prefetchEnabled,
          onChanged: (value) => save(config.copyWith(prefetchEnabled: value)),
        ),
        if (config.prefetchEnabled)
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _NumberField(
                label: l10n.desktopCachePrefetchThreshold,
                helper: l10n.desktopCachePrefetchThresholdHint,
                value: _prefetchThreshold,
                onChanged: (value) => _prefetchThreshold = value,
              ),
              _NumberField(
                label: l10n.desktopCachePrefetchBefore,
                helper: l10n.desktopCachePrefetchBeforeHint,
                value: _prefetchBefore,
                onChanged: (value) => _prefetchBefore = value,
              ),
            ],
          ),
        if (_invalid)
          Text(
            l10n.desktopCacheInvalidNumbers,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: context.colorScheme.error),
          ),
        if (error != null)
          Text(
            l10n.desktopCacheSaveFailed(error.message),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: context.colorScheme.error),
          ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final String? helper;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _numberWidth,
      child: TextFormField(
        // `initialValue` with a key tied to the label keeps the field's own text while a poll
        // rebuilds the card; the draft is what a save reads.
        initialValue: value,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, helperText: helper),
        style: AppTextStyle.callout.of(context),
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
