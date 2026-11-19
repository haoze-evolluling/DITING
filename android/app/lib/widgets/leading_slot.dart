import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:material_ui/material_ui.dart';

/// Reserves the wide leading column an app-icon row already occupies, so a glyph row stacked with
/// it keeps the same text edge.
///
/// `ListTile` starts the title at `max(minLeadingWidth, leading.width) + horizontalTitleGap`, and
/// the Material 3 `minLeadingWidth` is 24 here (the project sets no `ListTileTheme`). A bare
/// `GlyphIcon` is 20–24 wide, so it would sit 16dp left of an `AppIconAvatar` (40) and 10dp left of
/// an `IconBadge(34)`. Wrapping the mark here pins the column at [width] for every row in the card.
class LeadingSlot extends StatelessWidget {
  const LeadingSlot({
    super.key,
    required this.child,
    this.width = appIconTileSize,
  });

  /// The mark to centre in the column: a glyph, an app icon or a badge.
  final Widget child;

  /// Column width; the app-icon rows set it, so they never need this wrapper.
  final double width;

  @override
  Widget build(BuildContext context) {
    // `heightFactor: 1` keeps the row height driven by the mark rather than by a 40dp box.
    return SizedBox(width: width, child: Align(heightFactor: 1, child: child));
  }
}
