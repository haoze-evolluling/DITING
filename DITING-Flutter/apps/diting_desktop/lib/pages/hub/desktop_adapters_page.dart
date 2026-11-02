/// The `hub` branch's adapter takeover page: which network connections the service can see, and which
/// of them currently have their DNS pointed at the local resolver.
///
/// The old desktop console's `DevicesView` → `network/AdaptersPanel.vue` is the functional blueprint.
/// The page never decides what is taken over: `/adapters` reports the adapters and `/status` reports
/// the takeover set, and every write re-reads both.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_adapters_models.dart';
import 'package:diting_desktop/data/api/desktop_adapters_providers.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/pages/hub/widgets/adapter_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopAdaptersPage extends ConsumerWidget {
  const DesktopAdaptersPage({super.key});

  static const path = '/hub/adapters';

  Future<void> _setAll(
    BuildContext context,
    WidgetRef ref, {
    required bool enable,
  }) async {
    final l10n = context.l10n;
    final error = await ref.read(desktopAdaptersProvider.notifier).setAll(enable);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enable ? l10n.desktopAdaptersAllOn : l10n.desktopAdaptersAllOff)
          : l10n.desktopAdaptersActionFailed(error.message),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    DesktopAdapter adapter,
    bool enable,
  ) async {
    final l10n = context.l10n;
    final name = adapter.name.isEmpty ? adapter.id : adapter.name;
    final error = await ref
        .read(desktopAdaptersProvider.notifier)
        .setAdapter(adapter.id, enable);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopAdaptersAdapterToggled(
              name,
              enable
                  ? l10n.desktopAdaptersAdapterOn
                  : l10n.desktopAdaptersAdapterOff,
            )
          : l10n.desktopAdaptersActionFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopAdaptersProvider);
    void retry() => ref.read(desktopAdaptersProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopAdaptersPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopAdaptersRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: switch (state) {
        DesktopAdaptersState(isLoading: true, adapters: []) => const Center(
          child: CommonCircleLoading.page(),
        ),
        DesktopAdaptersState(adapters: [], error: final error?) => _Unavailable(
          error: error,
          onRetry: retry,
        ),
        DesktopAdaptersState(adapters: []) => _Empty(onRetry: retry),
        _ => PageBody(
          children: [
            state.isStale
                ? StaleStatusNotice(onRetry: retry)
                : const SizedBox.shrink(),
            DesktopCardBoard(
              cards: [
                _TakeoverSummaryCard(
                  active: state.takeoverActive,
                  saving: state.saving,
                  onSetAll: (enable) => unawaited(
                    _setAll(context, ref, enable: enable),
                  ),
                ),
                for (final adapter in state.adapters)
                  AdapterCard(
                    adapter: adapter,
                    takenOver: state.isTakenOver(adapter),
                    saving: state.saving,
                    onToggle: (enable) => unawaited(
                      _toggle(context, ref, adapter, enable),
                    ),
                  ),
              ],
            ),
          ],
        ),
      },
    );
  }
}

class _TakeoverSummaryCard extends StatelessWidget {
  const _TakeoverSummaryCard({
    required this.active,
    required this.saving,
    required this.onSetAll,
  });

  final bool active;
  final bool saving;
  final ValueChanged<bool> onSetAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopAdaptersSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: l10n.desktopAdaptersSectionTitle,
            leading: [
              DashboardChip(
                label: active
                    ? l10n.desktopAdaptersProtecting
                    : l10n.desktopAdaptersInactive,
                tone: active ? DashboardChipTone.ok : DashboardChipTone.idle,
                dot: active,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopAdaptersSectionBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: active
                ? OutlinedButton.icon(
                    onPressed: saving ? null : () => onSetAll(false),
                    icon: const GlyphIcon(AppGlyphs.undo, size: 16),
                    label: Text(l10n.desktopAdaptersRestoreAll),
                  )
                : FilledButton.tonalIcon(
                    onPressed: saving ? null : () => onSetAll(true),
                    icon: const GlyphIcon(AppGlyphs.verified, size: 16),
                    label: Text(l10n.desktopAdaptersTakeoverAll),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: NullStatusIllustration.connections,
            label: l10n.desktopAdaptersEmpty,
            description: l10n.desktopAdaptersEmptyBody,
            action: FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.desktopAdaptersRefresh),
            ),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.error, required this.onRetry});

  final DesktopApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: error.unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: l10n.desktopAdaptersLoadFailed,
            description: error.unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : error.message,
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
