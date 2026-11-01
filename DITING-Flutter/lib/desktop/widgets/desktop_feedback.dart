/// The two things every hub write path says: a confirmation before a destructive call, and a
/// transient answer afterwards. Shared so a page cannot invent its own dialog shape or snackbar.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// One confirmation dialog. Returns true only when the user pressed the confirm action.
Future<bool> confirmDesktopAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = true,
  bool showCancel = true,
}) async {
  final result = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: title,
      destructive: destructive,
      actions: [
        if (showCancel)
          TextButton(
            onPressed: () => popFloatingDialog(context, false),
            child: Text(context.l10n.commonCancel),
          ),
        TextButton(
          onPressed: () => popFloatingDialog(context, true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(body),
    ),
  );
  return result == true;
}

/// A transient answer for a write. The service's own message is used on failure.
void showDesktopMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
