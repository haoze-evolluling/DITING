// The app's in-place picker: the current value and a down chevron that opens the same
// [CommonPopupMenu] the rest of the app uses, so a select never falls back to the platform
// dropdown and never draws a field-like box that no other page uses.

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/popup.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:material_ui/material_ui.dart';

typedef SelectOption<T> = (T value, String label);

String _labelOf<T>(List<SelectOption<T>> items, T value) {
  for (final item in items) {
    if (item.$1 == value) {
      return item.$2;
    }
  }
  return '';
}

/// A compact inline picker: the current value and a chevron. Tapping opens [CommonPopupMenu]
/// with the current entry checked. Mirrors the window picker on the log stats card, so every
/// select in the app reads the same way.
class PopupSelectButton<T> extends StatelessWidget {
  const PopupSelectButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.semanticLabel,
  });

  final T value;
  final List<SelectOption<T>> items;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurfaceVariant;
    return CommonPopupBox(
      targetBuilder: (open) => Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          customBorder: AppShape.all(AppCorner.sm),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Text(
                  _labelOf(items, value),
                  style: AppTextStyle.callout.of(context).copyWith(color: color),
                ),
                GlyphIcon(AppGlyphs.chevronDown, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          for (final item in items)
            CommonPopupMenuItem(
              label: item.$2,
              checked: item.$1 == value,
              onPressed: () => onChanged(item.$1),
            ),
        ],
      ),
    );
  }
}
