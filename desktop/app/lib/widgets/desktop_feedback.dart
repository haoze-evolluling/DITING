library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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

void showDesktopMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
