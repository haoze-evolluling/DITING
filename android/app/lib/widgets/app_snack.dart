import 'package:material_ui/material_ui.dart';

/// One-line floating SnackBar: the single helper for transient feedback.
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
