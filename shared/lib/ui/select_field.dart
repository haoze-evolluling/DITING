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
          customBorder: AppShape.standard,
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  Text(
                    _labelOf(items, value),
                    style: AppTextRole.body.of(context).copyWith(color: color),
                  ),
                  GlyphIcon(AppGlyphs.chevronDown, size: 16, color: color),
                ],
              ),
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
