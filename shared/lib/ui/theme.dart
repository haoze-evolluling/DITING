// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/metrics.dart';
import 'package:material_ui/material_ui.dart';


class CommonMinIconButtonTheme extends StatelessWidget {
  final Widget child;

  const CommonMinIconButtonTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          iconSize: 20.ap(context),
        ).merge(IconButtonTheme.of(context).style),
      ),
      child: child,
    );
  }
}
