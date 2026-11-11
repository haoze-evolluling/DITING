/// The dashboard's status tiles that are not figures: the host service.
///
/// The home board is read-only, so the switch tiles that used to live here (adapter takeover and
/// the filter pause) moved to the pages that own those settings — `hub/adapters` and
/// `hub/filter-config`. What stays is a status tile, which reports and does not act.
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

/// The host service, not the DNS listener: installing it is what keeps resolution alive after this
/// window closes.
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
    // The trailing chip is a desktop-row luxury: at phone width the title and the state chip
    // already fill the header row.
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
