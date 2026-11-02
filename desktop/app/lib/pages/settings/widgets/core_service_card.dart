/// The host's core service, read-only: whether it is installed, whether it runs, and whether the
/// host starts it on boot.
///
/// The old desktop console's `ServicePanel.vue` / `CoreServiceCard.vue` managed the service through
/// native calls. Over the HTTP API only `/service/status` exists, so this card reports the host's
/// answer and says plainly that installing, starting and the boot registration happen on the host —
/// exactly the state the old console showed in web mode.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CoreServiceCard extends ConsumerWidget {
  const CoreServiceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopServiceStatusProvider);
    return DashboardCard(
      semanticLabel: l10n.desktopServiceCoreTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: l10n.desktopServiceCoreTitle,
            leading: [
              DashboardChip(
                label: state == null
                    ? l10n.desktopServiceUnknown
                    : !state.installed
                    ? l10n.desktopServiceNotInstalled
                    : state.running
                    ? l10n.desktopServiceRunning
                    : l10n.desktopServiceStopped,
                tone: state == null
                    ? DashboardChipTone.idle
                    : state.running
                    ? DashboardChipTone.ok
                    : DashboardChipTone.warn,
                dot: state?.running ?? false,
              ),
            ],
            trailing: [
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: AppGlyphs.refresh,
                  tooltip: l10n.desktopServiceRefresh,
                  size: 28,
                  glyphSize: 15,
                  onPressed: () =>
                      unawaited(ref.read(desktopServiceStatusProvider.notifier).refresh()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopServiceCoreBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          _Row(
            label: l10n.desktopServiceState,
            value: state?.stateText.isNotEmpty == true
                ? state!.stateText
                : l10n.desktopServiceUnknown,
          ),
          _Row(
            label: l10n.desktopServiceAutoStart,
            value: switch (state?.autoStart) {
              true => l10n.desktopServiceAutoStartOn,
              false => l10n.desktopServiceAutoStartOff,
              _ => l10n.desktopServiceAutoStartUnknown,
            },
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopServiceCoreFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
          ),
        ],
      ),
    );
  }
}
