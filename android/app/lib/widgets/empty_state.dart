import 'package:material_ui/material_ui.dart';

/// Gives `NullStatus` a minimum height, not a fixed one: under a fixed height it clips instead of
/// overflowing, cutting off buttons sized by data. A lower bound keeps short content centred and
/// lets long content grow the page.
class EmptyStateBox extends StatelessWidget {
  const EmptyStateBox({super.key, required this.child, this.minHeight = 240});

  final Widget child;

  /// Floor height so the empty state does not shrink on tall screens.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: child,
    );
  }
}
