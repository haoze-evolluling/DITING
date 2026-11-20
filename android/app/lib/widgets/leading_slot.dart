import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:material_ui/material_ui.dart';

class LeadingSlot extends StatelessWidget {
  const LeadingSlot({
    super.key,
    required this.child,
    this.width = appIconTileSize,
  });

  final Widget child;

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: Align(heightFactor: 1, child: child));
  }
}
