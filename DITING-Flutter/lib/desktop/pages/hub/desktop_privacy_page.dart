/// The `hub` branch's security and privacy page: the protocol-hardening switches, the ECS policy and
/// the two built-in defence modules (rebinding and hosts).
///
/// The old desktop console (`DevicesView.vue` and its `PrivacyPanel`) is the functional blueprint. The
/// page owns no DNS logic: it reads `/api/v1/status` and posts each patch to its own endpoint.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_privacy_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/privacy_defence_card.dart';
import 'package:diting/desktop/pages/hub/widgets/privacy_ecs_card.dart';
import 'package:diting/desktop/pages/hub/widgets/privacy_protocol_card.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Two columns appear only once both cards still fit their fields; below this they stack.
const double _wideBreakpoint = 980;
const double _contentMaxWidth = 1200;

class DesktopPrivacyPage extends ConsumerWidget {
  const DesktopPrivacyPage({super.key});

  static const path = '/hub/privacy';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopPrivacyProvider);
    final config = state.config;
    void retry() => ref.read(desktopPrivacyProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopPrivacyPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopPrivacyRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: config == null
          ? _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: retry,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                final side = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: dashboardCardGap,
                  children: [
                    PrivacyEcsCard(config: config, saving: state.saving),
                    PrivacyDefenceCard(config: config, saving: state.saving),
                  ],
                );
                final protocol = PrivacyProtocolCard(
                  config: config,
                  saving: state.saving,
                );
                return PageBody(
                  children: [
                    state.isStale
                        ? StaleStatusNotice(onRetry: retry)
                        : const SizedBox.shrink(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _contentMaxWidth,
                          ),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: dashboardCardGap,
                                  children: [
                                    Expanded(child: protocol),
                                    Expanded(child: side),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: dashboardCardGap,
                                  children: [protocol, side],
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
            label: l10n.desktopPrivacyLoadFailed,
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
