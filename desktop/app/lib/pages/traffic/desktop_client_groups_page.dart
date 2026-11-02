/// The home branch's client-group page: one card that edits the whole `/clients/groups`
/// document and saves it in one request.
///
/// The old desktop console's `ClientGroupsCard.vue` is the functional blueprint. It is a sub-page
/// (`/home/client-groups`) rather than a second card on the home board, because the editor is long
/// and the device cards stay about who is connected.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_client_groups_providers.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_groups_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopClientGroupsPage extends ConsumerWidget {
  const DesktopClientGroupsPage({super.key});

  static const path = '/home/client-groups';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopClientGroupsProvider);
    final data = state.data;
    void retry() => ref.read(desktopClientGroupsProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopGroupsPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopGroupsRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: data == null
          ? _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: retry,
            )
          : PageBody(
              children: [
                state.isStale
                    ? StaleStatusNotice(onRetry: retry)
                    : const SizedBox.shrink(),
                DesktopCardBoard(
                  cards: [ClientGroupsCard(data: data, saving: state.saving)],
                ),
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
            label: l10n.desktopGroupsLoadFailed,
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
