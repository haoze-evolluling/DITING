/// A label, a glyph and a chevron that opens a menu of checked entries: the filter/picker shape the
/// old desktop console and the log branch both use. Shared so a new page cannot invent a picker.
library;

import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class DesktopPicker extends StatelessWidget {
  const DesktopPicker({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    required this.label,
    required this.items,
    this.active = false,
  });

  final Glyph glyph;
  final String semanticLabel;
  final String label;

  /// Whether the picker narrows something; an active one is drawn in the accent colour.
  final bool active;

  final List<CommonPopupMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = active ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return CommonPopupBox(
      targetBuilder: (open) => Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          customBorder: AppShape.all(AppCorner.sm),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                GlyphIcon(glyph, size: 16, color: color),
                Text(
                  label,
                  style: AppTextStyle.callout.of(context).copyWith(color: color),
                ),
                GlyphIcon(AppGlyphs.chevronDown, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
      popupBuilder: (_) => CommonPopupMenu(items: items),
    );
  }
}
