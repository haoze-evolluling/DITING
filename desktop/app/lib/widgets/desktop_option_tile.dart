/// One selectable option inside a dashboard card: the title with its mark, and the note under it.
///
/// Every "pick one of these" group on the desktop hub (upstream scheduling, blocking response, the
/// `ANY` response) is the same control, so the choice lives here instead of in three copies. The
/// background is the card's tone level — the dashboard card is its own surface, so an unselected
/// tile still reads as a button rather than as loose text.
library;

import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class DesktopOptionTile extends StatelessWidget {
  const DesktopOptionTile({
    super.key,
    required this.label,
    this.description,
    required this.selected,
    required this.onPressed,
  });

  final String label;

  /// The one or two sentences that tell the options apart; omitted for a bare label tile.
  final String? description;

  final bool selected;
  final VoidCallback? onPressed;

  /// Lines the note may take before it ellipsizes: a tile in a two-column grid is narrower than a
  /// full-width row and wraps sooner.
  static const int _descriptionMaxLines = 3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = selected ? colorScheme.onPrimary : null;
    return CommonCard(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Row(
            spacing: 8,
            children: [
              GlyphIcon(
                selected ? AppGlyphs.checkCircle : AppGlyphs.picker,
                size: 18,
                color: foreground,
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context)
                      .copyWith(color: foreground),
                ),
              ),
            ],
          ),
          if (description case final description?)
            Text(
              description,
              maxLines: _descriptionMaxLines,
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
    );
  }
}
