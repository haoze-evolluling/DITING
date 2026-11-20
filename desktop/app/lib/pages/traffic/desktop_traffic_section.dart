library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_traffic_providers.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_list_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

List<Widget> desktopTrafficCards(BuildContext context, WidgetRef ref) {
  final state = ref.watch(desktopTrafficProvider);
  final limits = state.limits;
  void retry() => ref.read(desktopTrafficProvider.notifier).reload();
  if (limits == null) {
    return [
      _TrafficUnavailableCard(
        loading: state.isLoading,
        error: state.error,
        onRetry: retry,
      ),
    ];
  }
  return [
    DesktopClientListCard(
      clients: state.clients,
      access: limits.access,
      saving: state.saving,
      loading: state.isLoading,
      onRefresh: retry,
    ),
  ];
}

class _TrafficUnavailableCard extends StatelessWidget {
  const _TrafficUnavailableCard({
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
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopTrafficPageTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: l10n.desktopTrafficPageTitle,
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CommonCircleLoading(size: 20)),
            )
          else
            Row(
              spacing: 8,
              children: [
                GlyphIcon(
                  AppGlyphs.warning,
                  size: 18,
                  color: colorScheme.warning,
                ),
                Expanded(
                  child: Text(
                    error?.unauthorized ?? false
                        ? l10n.desktopBackendUnauthorizedBody
                        : l10n.desktopTrafficLoadFailed,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.rowTitle(context),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  child: Text(l10n.desktopRetry),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
