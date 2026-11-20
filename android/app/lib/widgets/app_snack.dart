import 'package:material_ui/material_ui.dart';

void showAppSnack(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration,
    ),
  );
}
