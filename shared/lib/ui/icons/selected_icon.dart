import 'package:material_ui/material_ui.dart';

const _duration = Duration(milliseconds: 350);

/// A navigation icon that crossfades to its filled variant when selected.
///
/// Tabler ships a `_filled` counterpart for only some icons; when [filledIcon]
/// is null the outline stays put and the surrounding navigation theme handles
/// the colour transition.
class SelectedIcon extends StatelessWidget {
  const SelectedIcon({
    super.key,
    required this.icon,
    this.filledIcon,
    required this.selected,
    this.size,
    this.color,
  });

  final IconData icon;
  final IconData? filledIcon;
  final bool selected;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final filledIcon = this.filledIcon;
    if (filledIcon == null) {
      return Icon(icon, size: size, color: color);
    }
    final target = selected ? filledIcon : icon;
    return AnimatedSwitcher(
      duration: _duration,
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Icon(target, key: ValueKey(target), size: size, color: color),
    );
  }
}
