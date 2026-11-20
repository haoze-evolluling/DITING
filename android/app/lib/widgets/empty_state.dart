import 'package:material_ui/material_ui.dart';

class EmptyStateBox extends StatelessWidget {
  const EmptyStateBox({super.key, required this.child, this.minHeight = 240});

  final Widget child;

  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: child,
    );
  }
}
