/// The four scheduling modes, as the console's `UpstreamPanel.vue` lays them out: a 2×2 grid of
/// selectable cards. Picking one saves the whole upstream config immediately, as the console does.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_upstream_models.dart';
import 'package:diting_desktop/pages/hub/widgets/upstream_common.dart';
import 'package:diting_desktop/widgets/desktop_option_tile.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class UpstreamModeCard extends StatelessWidget {
  const UpstreamModeCard({
    super.key,
    required this.config,
    required this.saving,
    required this.onChanged,
  });

  final DesktopUpstreamConfig config;
  final bool saving;
  final ValueChanged<DesktopUpstreamConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopUpstreamModeTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sliders,
            title: l10n.desktopUpstreamModeTitle,
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardChip(
                  label: desktopUpstreamModeLabel(context, config.mode),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopUpstreamModeBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 520;
              final cards = [
                for (final mode in desktopUpstreamModes)
                  DesktopOptionTile(
                    label: desktopUpstreamModeLabel(context, mode),
                    description: desktopUpstreamModeBody(context, mode),
                    selected: config.mode == mode,
                    onPressed: saving || config.mode == mode
                        ? null
                        : () => onChanged(config.copyWith(mode: mode)),
                  ),
              ];
              if (!twoColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: cards,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ModeRow(children: [cards[0], cards[1]]),
                  const SizedBox(height: 8),
                  _ModeRow(children: [cards[2], cards[3]]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Two tiles on one line, both stretched to the taller one: an option grid whose cells change
/// height with their description reads as misaligned.
class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [for (final child in children) Expanded(child: child)],
      ),
    );
  }
}
