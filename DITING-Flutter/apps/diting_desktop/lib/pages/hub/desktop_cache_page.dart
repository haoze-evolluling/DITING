/// The `hub` branch's cache page: the acceleration engine, the service's telemetry, the ten hottest
/// names, the policy form, persistence and the exclude rules, over the cached-entry table.
///
/// The old desktop console (`ResolveView.vue` and its `accel/CachePanel.vue`) is the functional
/// blueprint. The page owns no cache logic: it polls `/api/v1/cache/stats|top|persist`, posts the
/// whole config to `/api/v1/cache/config`, and shows what the service re-reads.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_config_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_entries_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_exclude_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_overview_cards.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_persist_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_top_card.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopCachePage extends ConsumerWidget {
  const DesktopCachePage({super.key});

  static const path = '/hub/cache';

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final stats = ref.read(desktopCacheSnapshotProvider).stats;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopCacheClearTitle,
      body: l10n.desktopCacheClearBody(stats?.entryCount ?? 0),
      confirmLabel: l10n.desktopCacheClear,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(desktopCacheActionProvider.notifier).clear();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopCacheClearDone
          : l10n.desktopCacheClearFailed(error.message),
    );
  }

  void _refresh(WidgetRef ref) {
    unawaited(ref.read(desktopCacheSnapshotProvider.notifier).refresh());
    unawaited(ref.read(desktopCacheConfigProvider.notifier).reload());
    ref.invalidate(desktopCacheEntriesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final snapshot = ref.watch(desktopCacheSnapshotProvider);
    final configState = ref.watch(desktopCacheConfigProvider);
    final action = ref.watch(desktopCacheActionProvider);
    final stats = snapshot.stats;
    void retry() => _refresh(ref);
    if (stats == null) {
      return CommonScaffold(
        title: l10n.desktopCacheTitle,
        body: _Unavailable(
          loading: snapshot.isLoading,
          error: snapshot.error,
          onRetry: retry,
        ),
      );
    }
    final config = configState.config;
    final cards = <Widget>[
      CacheEngineCard(
        stats: stats,
        enabled: config?.enabled ?? stats.enabled,
        busy: configState.saving || config == null,
        clearing: action.isBusyWith(DesktopCacheAction.clear),
        onToggle: config == null
            ? null
            : (value) => unawaited(
                ref
                    .read(desktopCacheConfigProvider.notifier)
                    .save(config.copyWith(enabled: value)),
              ),
        onRefresh: retry,
        onClear: () => _clear(context, ref),
      ),
      CacheTelemetryCard(stats: stats),
      CacheTopCard(domains: snapshot.topDomains),
      const CacheConfigCard(),
      CachePersistCard(persist: snapshot.persist),
      CacheExcludeCard(persist: snapshot.persist),
      const CacheEntriesCard(),
    ];
    return CommonScaffold(
      title: l10n.desktopCacheTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopCacheRefresh,
          onPressed: () => _refresh(ref),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: PageBody(
        children: [
          if (snapshot.isStale) StaleStatusNotice(onRetry: retry),
          DesktopCardBoard(cards: cards),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) return const Center(child: CommonCircleLoading.page());
    final unauthorized = error?.unauthorized ?? false;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: l10n.desktopCacheLoadFailed,
            description: unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : error?.message,
            action: FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.desktopRetry),
            ),
          ),
        ),
      ),
    );
  }
}
