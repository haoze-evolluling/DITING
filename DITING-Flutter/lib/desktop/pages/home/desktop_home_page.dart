import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/dashboard_models.dart';
import 'package:diting/data/vpn/power_state.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_density.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/pages/home/widgets/home_headline.dart';
import 'package:diting/state/dashboard_layout_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Desktop home: the Android dashboard skeleton — power button, sentence, card board — over the
/// same density scope, the same card frames and the same stored layout.
///
/// The board keeps the user's card order but not yet the cards' data: the tunnel is controlled over
/// the local HTTP API (step 4), so the power button says it is not wired up instead of pretending to
/// run, and every card shows the same "not connected" chip where Android shows figures.
class DesktopHomePage extends ConsumerWidget {
  const DesktopHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashboardDensityScopeHost(
      child: CommonScaffold(
        // No work mode on desktop yet, so the title stays on the normal-mode string.
        title: context.l10n.homeTitleNormal,
        body: PageBody(
          children: [
            ...buildHomeHeadline(
              context: context,
              ref: ref,
              state: PowerState.stopped,
              onPressed: () => _showPending(context),
            ),
            const DesktopHomeBoard(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showPending(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.homePowerPending),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }
}

/// Same list, same paddings, same gaps and the same entrance animation as `DashboardBoard`; only
/// the card bodies differ, because their data sources do.
class DesktopHomeBoard extends ConsumerWidget {
  const DesktopHomeBoard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(dashboardWidgetsProvider);
    final side = dashboardMobileSideOf(MediaQuery.sizeOf(context).width);
    if (widgets.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(side, 40, side, 0),
        child: NullStatus(
          illustration: NullStatusIllustration.data,
          label: context.l10n.dashboardEmptyLabel,
          description: context.l10n.dashboardEmptyDescription,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: dashboardCardGap,
        children: [
          for (final widget in widgets)
            DashboardCardEntrance(
              key: ValueKey(widget),
              child: _PendingCard(widget: widget),
            ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.widget});

  final DashboardWidget widget;

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: widget.label(l10n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: _glyphOf(widget),
            title: widget.label(l10n),
          ),
          SizedBox(height: 12 * scale),
          // One chip instead of a paragraph: the card's state really is "not connected", and it
          // reads like the other status badges on the board.
          Row(
            children: [
              DashboardChip(label: l10n.commonPendingTitle, dot: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// The glyph each Android card puts in its header; kept here so the desktop card titles line up
/// with the ones users already know.
Glyph _glyphOf(DashboardWidget widget) => switch (widget) {
  DashboardWidget.provider => AppGlyphs.dns,
  DashboardWidget.resolution => AppGlyphs.shuffle,
  DashboardWidget.status => AppGlyphs.status,
  DashboardWidget.networkSpeed => AppGlyphs.speed,
  DashboardWidget.siteLatency => AppGlyphs.speed,
  DashboardWidget.memoryInfo => AppGlyphs.memory,
  DashboardWidget.intranetIp => AppGlyphs.devices,
};
