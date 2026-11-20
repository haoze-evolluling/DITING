import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, this.gap = 8});

  final List<Widget> children;

  final double gap;

  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: children.length,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.disabled = false,
  });

  final String label;
  final bool selected;

  final VoidCallback? onPressed;

  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return TonalChip(
      label: label,
      color: selected
          ? colorScheme.primary
          : context.raisedSurfaceLevel.colorOf(colorScheme),
      foregroundColor: _foreground(colorScheme),
      onPressed: onPressed,
    );
  }

  Color _foreground(ColorScheme colorScheme) {
    if (disabled) return colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
    if (selected) return colorScheme.onPrimary;
    return colorScheme.onSurfaceVariant;
  }
}
