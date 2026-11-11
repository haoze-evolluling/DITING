/// Cache persistence: whether the in-memory answers are written to disk, how often, and where.
///
/// The old desktop console's `CachePersistCard.vue` is the blueprint: the switch applies at once, the
/// interval travels on its own (clamped to 30–86400) and the file path is read-only because the service
/// owns the data layout. The two manual operations are [CacheSnapshotCard], because a settings card and
/// a pair of destructive-ish buttons answer different questions.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const int _minInterval = 30;
const int _maxInterval = 86400;

class CachePersistCard extends ConsumerStatefulWidget {
  const CachePersistCard({super.key, required this.persist});

  /// The service's persistence status; null when this build of the service does not report it.
  final DesktopCachePersist? persist;

  @override
  ConsumerState<CachePersistCard> createState() => _CachePersistCardState();
}

class _CachePersistCardState extends ConsumerState<CachePersistCard> {
  String _interval = '';

  Future<DesktopApiException?> _save(
    DesktopCacheConfig next,
    String successMessage,
  ) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopCacheConfigProvider.notifier)
        .save(next);
    if (!mounted) return error;
    if (error == null) {
      // The file path, the interval the service actually runs and the last write failure all come
      // from the status endpoint, so a successful save re-reads it.
      unawaited(ref.read(desktopCacheSnapshotProvider.notifier).refresh());
    }
    showDesktopMessage(
      context,
      error == null
          ? successMessage
          : l10n.desktopCacheSaveFailed(error.message),
    );
    return error;
  }

  /// Empty or non-positive falls back to the service default; anything else is clamped, exactly as
  /// the console does. Zero is not "never" here: the service cannot tell it from a missing field.
  Future<void> _submitInterval(DesktopCacheConfig config) async {
    final raw = int.tryParse(_interval);
    final seconds = raw == null || raw <= 0
        ? desktopCacheDefaultPersistSeconds
        : raw.clamp(_minInterval, _maxInterval);
    final error = await _save(
      config.copyWith(persistIntervalSeconds: seconds),
      context.l10n.desktopCachePersistIntervalSaved,
    );
    if (error != null || !mounted) return;
    // Show what the service kept: it clamps the interval, so the typed value is not the answer.
    final saved = ref.read(desktopCacheConfigProvider).config;
    if (saved != null) {
      setState(() => _interval = '${saved.effectivePersistIntervalSeconds}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopCacheConfigProvider);
    final config = state.config;
    final persist = widget.persist;
    if (config != null && _interval.isEmpty) {
      _interval = '${config.effectivePersistIntervalSeconds}';
    }
    final enabled = config?.persistEnabled ?? false;
    return DashboardCard(
      semanticLabel: l10n.desktopCachePersistTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sync,
            title: l10n.desktopCachePersistTitle,
            leading: [
              DashboardChip(
                label: enabled
                    ? l10n.desktopCachePersistOn
                    : l10n.desktopCachePersistOff,
                tone: enabled ? DashboardChipTone.ok : DashboardChipTone.idle,
              ),
            ],
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardSwitch(
                  value: enabled,
                  semanticLabel: l10n.desktopCachePersistTitle,
                  onChanged: config == null
                      ? null
                      : (value) => unawaited(
                          _save(
                            config.copyWith(persistEnabled: value),
                            value
                                ? l10n.desktopCachePersistToggleOn
                                : l10n.desktopCachePersistToggleOff,
                          ),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopCachePersistBody,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (config == null)
            _Unavailable(
              isLoading: state.isLoading,
              error: state.error,
              onRetry: ref.read(desktopCacheConfigProvider.notifier).reload,
            )
          else if (enabled) ...[
            Row(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 240,
                  child: TextFormField(
                    initialValue: _interval,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.desktopCachePersistInterval,
                      helperText: l10n.desktopCachePersistIntervalHint,
                      helperMaxLines: 3,
                    ),
                    style: AppTextStyle.callout.of(context),
                    onChanged: (value) => _interval = value,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TonalButton(
                    size: TonalButtonSize.compact,
                    glyph: AppGlyphs.check,
                    label: l10n.commonSave,
                    onPressed: state.saving
                        ? null
                        : () => unawaited(_submitInterval(config)),
                  ),
                ),
              ],
            ),
            if (persist?.path.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              _PathBlock(path: persist!.path),
            ],
            if (persist?.lastError.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              _LastError(message: persist!.lastError),
            ],
          ],
        ],
      ),
    );
  }
}

class _PathBlock extends StatelessWidget {
  const _PathBlock({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return DashboardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            context.l10n.desktopCachePersistPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          SelectableText(
            path,
            maxLines: 2,
            style: AppTextStyle.caption1.of(context).toTabular,
          ),
        ],
      ),
    );
  }
}

class _LastError extends StatelessWidget {
  const _LastError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: GlyphIcon(AppGlyphs.warning, size: 14, color: color),
        ),
        Expanded(
          child: Text(
            context.l10n.desktopCachePersistLastError(message),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1.of(context).copyWith(color: color),
          ),
        ),
      ],
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
