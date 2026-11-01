/// The `hub` branch's encrypted DNS server: the DoT / DoH / DoQ listeners, the certificate, discovery,
/// reverse-proxy trust and the mobile profile.
///
/// The old desktop console (`DevicesView.vue` and its `encrypted/EncryptedDNSPanel`) is the functional
/// blueprint. The page owns no TLS logic: it reads `/api/v1/encrypted/dns/status` and adopts the whole
/// status the service answers with after every write.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/encrypted_cert_card.dart';
import 'package:diting/desktop/pages/hub/widgets/encrypted_extras_card.dart';
import 'package:diting/desktop/pages/hub/widgets/encrypted_listeners_card.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _wideBreakpoint = 980;
const double _contentMaxWidth = 1200;

class DesktopEncryptedPage extends ConsumerWidget {
  const DesktopEncryptedPage({super.key});

  static const path = '/hub/encrypted-dns';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopEncryptedProvider);
    final status = state.status;
    void retry() => ref.read(desktopEncryptedProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopEncryptedPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopEncryptedRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: status == null
          ? _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: retry,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                final listeners = EncryptedListenersCard(
                  status: status,
                  saving: state.saving,
                );
                final side = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: dashboardCardGap,
                  children: [
                    EncryptedCertCard(status: status, saving: state.saving),
                    EncryptedExtrasCard(status: status, saving: state.saving),
                  ],
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
                                    Expanded(child: listeners),
                                    Expanded(child: side),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: dashboardCardGap,
                                  children: [listeners, side],
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
            label: l10n.desktopEncryptedLoadFailed,
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
