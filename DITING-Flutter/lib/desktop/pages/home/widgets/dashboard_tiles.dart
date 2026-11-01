/// The dashboard's interactive row: two switches and the host service, all three sized to one
/// 64-high row like upstream's control bar.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_density.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Vertical padding that leaves room for the 32-high switch track inside a control row.
EdgeInsets _tilePadding() =>
    const EdgeInsets.symmetric(horizontal: 18, vertical: 8);

/// One switch behind a title and a state word. The card owns the tap, so the switch itself is
/// pointer-transparent: two tap targets for one boolean only invite a double toggle.
class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.glyph,
    required this.title,
    required this.state,
    required this.value,
    required this.onChanged,
    required this.busy,
    required this.onTap,
  });

  final Glyph glyph;
  final String title;
  final String state;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DashboardCard(
      padding: _tilePadding(),
      semanticLabel: title,
      onTap: busy ? null : onTap,
      child: Row(
        spacing: 10,
        children: [
          GlyphIcon(glyph, size: 18, color: colorScheme.onSurfaceVariant),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(
                    context,
                    color: value ? colorScheme.success : null,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox.square(dimension: 20, child: CommonCircleLoading())
          else
            IgnorePointer(
              child: DashboardSwitch(
                value: value,
                onChanged: onChanged,
                semanticLabel: title,
              ),
            ),
        ],
      ),
    );
  }
}

/// Takes over the machine's adapter DNS settings.
class TakeoverTile extends ConsumerWidget {
  const TakeoverTile({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final control = ref.watch(desktopControlProvider);
    final active = status.takeover.active;
    final busy = control.pending == DesktopControlAction.takeover;
    void toggle(bool next) =>
        ref.read(desktopControlProvider.notifier).setTakeover(next);
    return _ControlTile(
      glyph: AppGlyphs.vpn,
      title: l10n.desktopTakeoverTitle,
      state: active ? l10n.desktopTakeoverOn : l10n.desktopTakeoverOff,
      value: active,
      onChanged: toggle,
      busy: busy,
      onTap: () => toggle(!active),
    );
  }
}

/// Pauses rule blocking without touching the rule lists.
class FilterPauseTile extends ConsumerWidget {
  const FilterPauseTile({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final control = ref.watch(desktopControlProvider);
    final paused = status.filter.paused;
    final busy = control.pending == DesktopControlAction.filter;
    // The switch means "blocking is on", the state word says which way it currently is.
    void toggle(bool enabled) =>
        ref.read(desktopControlProvider.notifier).setFilterPaused(!enabled);
    return _ControlTile(
      glyph: AppGlyphs.block,
      title: l10n.desktopFilterPauseTitle,
      state: paused ? l10n.desktopFilterPaused : l10n.desktopFilterActive,
      value: !paused,
      onChanged: toggle,
      busy: busy,
      onTap: () => toggle(paused),
    );
  }
}

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
