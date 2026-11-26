import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

enum UnsavedChangesChoice {
  cancel,

  discard,

  save,
}

Future<UnsavedChangesChoice> showUnsavedChangesDialog(
  BuildContext context, {
  String? title,
  String? message,
}) async {
  final choice = await showFloatingDialog<UnsavedChangesChoice>(
    context: context,
    child: CommonDialog(
      title: title ?? context.l10n.commonSaveChangesTitle,
      actions: [
        TextButton(
          onPressed: () =>
              popFloatingDialog(context, UnsavedChangesChoice.discard),
          child: Text(context.l10n.commonDiscard),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(context, UnsavedChangesChoice.save),
          child: Text(context.l10n.commonSave),
        ),
      ],
      child: Text(message ?? context.l10n.commonSaveChangesMessage),
    ),
  );
  return choice ?? UnsavedChangesChoice.cancel;
}

class UnsavedChangesScope extends StatelessWidget {
  const UnsavedChangesScope({
    super.key,
    required this.child,
    required this.hasUnsavedChanges,
    required this.onResolve,
  });

  final Widget child;

  final bool Function() hasUnsavedChanges;

  final Future<bool> Function() onResolve;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasUnsavedChanges(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !context.mounted) {
          return;
        }
        final leave = await onResolve();
        if (!leave || !context.mounted) {
          return;
        }
        Navigator.of(context).pop();
      },
      child: child,
    );
  }
}
