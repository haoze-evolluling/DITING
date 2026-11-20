library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class HostServiceCard extends ConsumerWidget {
  const HostServiceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final value = ref.watch(desktopServiceStatusProvider);
    final (label, tone) = switch (value) {
      null => (l10n.stateStopped, DashboardChipTone.idle),
      final CoreServiceState state when !state.installed => (
        l10n.desktopServiceNotInstalled,
        DashboardChipTone.warn,
      ),
      final CoreServiceState state when state.running => (
        l10n.stateRunning,
        DashboardChipTone.ok,
      ),
      _ => (l10n.stateStopped, DashboardChipTone.idle),
    };
    final autoStart = value?.autoStart;
    final wide = DashboardDensityScope.of(context).isDesktop;
    return DashboardCard(
      semanticLabel: l10n.desktopServiceHostTitle,
      padding: dashboardCardPadding(DashboardDensityScope.of(context)),
      child: DashboardCardHeader(
        glyph: AppGlyphs.layers,
        title: l10n.desktopServiceHostTitle,
        leading: [DashboardChip(label: label, tone: tone, dot: true)],
        trailing: [
          if (wide && autoStart != null)
            DashboardChip(
              label: l10n.desktopServiceAutoStart,
              tone: autoStart ? DashboardChipTone.ok : DashboardChipTone.idle,
            ),
        ],
      ),
    );
  }
}
