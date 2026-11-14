// A select that opens the app's own [CommonPopupMenu] instead of the platform dropdown,
// in the three shapes the app needs: a filled labelled field on a page, a field inside a
// dialog that borrows the ambient [InputDecorationTheme], and a compact inline picker.

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/popup.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:material_ui/material_ui.dart';

typedef SelectOption<T> = (T value, String label);

/// The one menu every select opens, so a picker never falls back to the platform dropdown.
CommonPopupMenu _selectMenu<T>(
  List<SelectOption<T>> items,
  T value,
  ValueChanged<T> onChanged,
) {
  return CommonPopupMenu(
    items: [
      for (final item in items)
        CommonPopupMenuItem(
          label: item.$2,
          checked: item.$1 == value,
          onPressed: () => onChanged(item.$1),
        ),
    ],
  );
}

String _labelOf<T>(List<SelectOption<T>> items, T value) {
  for (final item in items) {
    if (item.$1 == value) {
      return item.$2;
    }
  }
  return '';
}

/// A labelled select on a page: the label sits above a filled field that shows the current
/// value, mirroring [LabeledInputField] so a picker reads as a field, not a bare dropdown.
class LabeledSelectField<T> extends StatelessWidget {
  const LabeledSelectField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final T value;
  final List<SelectOption<T>> items;
  final ValueChanged<T> onChanged;

  /// Omitted when the surrounding section already names the field.
  final String? label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        if (label != null) Text(label, style: context.listTitleStyle),
        CommonPopupBox(
          placement: PopupPlacement.belowPoint,
          popupBuilder: (_) => _selectMenu(items, value, onChanged),
          targetBuilder: (open) => Semantics(
            button: true,
            label: label,
            child: Material(
              color: context.raisedSurfaceLevel.colorOf(colorScheme),
              borderRadius: AppRadius.md,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? open : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _labelOf(items, value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.listTitleStyle,
                        ),
                      ),
                      GlyphIcon(
                        AppGlyphs.chevronDown,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A select that sits among Material fields, such as in a dialog: it borrows the ambient
/// [InputDecorationTheme] through an [InputDecorator], so it matches the outlined fields
/// beside it, while still opening the app's own menu.
class PopupSelectField<T> extends StatelessWidget {
  const PopupSelectField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final T value;
  final List<SelectOption<T>> items;
  final ValueChanged<T> onChanged;
  final String? label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonPopupBox(
      placement: PopupPlacement.belowPoint,
      popupBuilder: (_) => _selectMenu(items, value, onChanged),
      targetBuilder: (open) => InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: InkWell(
          onTap: enabled ? open : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _labelOf(items, value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GlyphIcon(
                AppGlyphs.chevronDown,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact inline picker for a list row or toolbar: the current value and a chevron.
class PopupSelectButton<T> extends StatelessWidget {
  const PopupSelectButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.glyph,
    this.semanticLabel,
  });

  final T value;
  final List<SelectOption<T>> items;
  final ValueChanged<T> onChanged;
  final Glyph? glyph;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = colorScheme.onSurfaceVariant;
    final glyph = this.glyph;
    return CommonPopupBox(
      placement: PopupPlacement.belowPoint,
      popupBuilder: (_) => _selectMenu(items, value, onChanged),
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
                if (glyph != null) GlyphIcon(glyph, size: 16, color: color),
                Flexible(
                  child: Text(
                    _labelOf(items, value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.listTitleStyle.copyWith(color: color),
                  ),
                ),
                GlyphIcon(AppGlyphs.chevronDown, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
