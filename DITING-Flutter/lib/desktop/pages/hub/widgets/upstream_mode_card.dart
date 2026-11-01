/// The four scheduling modes, as the console's `UpstreamPanel.vue` lays them out: a 2×2 grid of
/// selectable cards. Picking one saves the whole upstream config immediately, as the console does.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_upstream_models.dart';
import 'package:diting/desktop/pages/hub/widgets/upstream_common.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
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
                  _ModeTile(
                    label: desktopUpstreamModeLabel(context, mode),
                    body: desktopUpstreamModeBody(context, mode),
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
                spacing: 8,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Expanded(child: cards[0]),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Expanded(child: cards[2]),
                      Expanded(child: cards[3]),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.body,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String body;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = selected ? colorScheme.onPrimary : null;
    return CommonCard(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: GlyphIcon(
              selected ? AppGlyphs.checkCircle : AppGlyphs.picker,
              size: 18,
              color: foreground,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(
                    context,
                  ).copyWith(color: foreground),
                ),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(
                    context,
                    color: selected
                        ? colorScheme.onPrimary.withValues(alpha: 0.85)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
