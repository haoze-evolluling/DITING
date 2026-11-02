import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// What the user chose after leaving a page that still has an uncommitted draft.
enum UnsavedChangesChoice {
  /// Stay on the page. Only produced by dismissing the dialog (barrier tap or back), since the pane
  /// itself offers just the two answers.
  cancel,

  /// Leave and drop the draft.
  discard,

  /// Commit the draft, then leave.
  save,
}

/// Asks whether to save the pending selection before going back. Both the title-bar arrow and the
/// system back gesture go through here, so a half-finished pick cannot be lost by accident.
/// [title] and [message] default to the generic wording of the ARB resources.
Future<UnsavedChangesChoice> showUnsavedChangesDialog(
  BuildContext context, {
  String? title,
  String? message,
}) async {
  final choice = await showFloatingDialog<UnsavedChangesChoice>(
    context: context,
    child: CommonDialog(
      title: title ?? context.l10n.commonSaveChangesTitle,
      // Two answers only: staying is what dismissing the pane does, so it needs no button.
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
  // A barrier tap returns null: treat it as "keep editing" rather than losing the draft.
  return choice ?? UnsavedChangesChoice.cancel;
}

/// Guards a page with uncommitted changes: the app bar arrow, the system back gesture and the
/// hardware back key all land on [onResolve] instead of popping straight away.
///
/// The page rebuilds whenever its draft changes, so [hasUnsavedChanges] is re-read on every build and
/// `canPop` stays in step with the draft.
class UnsavedChangesScope extends StatelessWidget {
  const UnsavedChangesScope({
    super.key,
    required this.child,
    required this.hasUnsavedChanges,
    required this.onResolve,
  });

  final Widget child;

  /// When false the route pops as usual.
  final bool Function() hasUnsavedChanges;

  /// Called only when there are pending changes; return true to let the page pop.
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
