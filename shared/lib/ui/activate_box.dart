// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:material_ui/material_ui.dart';

class ActivateBox extends StatelessWidget {
  final Widget child;
  final bool active;

  const ActivateBox({super.key, required this.child, this.active = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(ignoring: !active, child: child);
  }
}
