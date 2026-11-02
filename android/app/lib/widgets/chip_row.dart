import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A horizontally scrolling row of selectable chips, fixed at 32 high. A `Wrap` leaves `TonalChip`
/// unconstrained on the cross axis, so it collapses and wraps; a horizontal `ListView` keeps a
/// constant height. Horizontal padding is the caller's job (16, like `ListHeader`).
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, this.gap = 8});

  final List<Widget> children;

  /// Gap between adjacent chips.
  final double gap;

  /// Pill height; `TonalChip` has no intrinsic height.
  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Viewport starts at 0 so chips can scroll to the screen edge.
        padding: EdgeInsets.zero,
        itemCount: children.length,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

/// A selected/unselected filter chip. Centralises the colours four pages used to duplicate
/// with the same ternaries.
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

  /// `null` when this option is already selected and needs no tap.
  final VoidCallback? onPressed;

  /// Disabled: keeps the tap (so the UI can explain why) but fades the label.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = disabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
        : selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    return TonalChip(
      label: label,
      color: selected
          ? colorScheme.primary
          : context.raisedSurfaceLevel.colorOf(colorScheme),
      foregroundColor: foreground,
      onPressed: onPressed,
    );
  }
}
