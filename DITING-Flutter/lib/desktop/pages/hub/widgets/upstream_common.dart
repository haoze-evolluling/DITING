/// Small, shared pieces of the hub's resolution pages: protocol names, mode metadata, and the
/// confirm/message helpers every write path uses. Nothing here decides DNS state; the service does.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The protocol names the console shows. They are wire names, not prose, so they stay untranslated.
String desktopProtocolLabel(String protocol) => switch (protocol) {
  'DOH' => 'DoH',
  'DOH3' => 'DoH3',
  'DOT' => 'DoT',
  'DOQ' => 'DoQ',
  _ => 'UDP 53',
};

String desktopUpstreamModeLabel(BuildContext context, String mode) {
  final l10n = context.l10n;
  return switch (mode) {
    'single' => l10n.desktopUpstreamModeSingle,
    'parallel_race' => l10n.desktopUpstreamModeRace,
    'smart_prediction' => l10n.desktopUpstreamModeSmart,
    _ => l10n.desktopUpstreamModeBackup,
  };
}

String desktopUpstreamModeBody(BuildContext context, String mode) {
  final l10n = context.l10n;
  return switch (mode) {
    'single' => l10n.desktopUpstreamModeSingleBody,
    'parallel_race' => l10n.desktopUpstreamModeRaceBody,
    'smart_prediction' => l10n.desktopUpstreamModeSmartBody,
    _ => l10n.desktopUpstreamModeBackupBody,
  };
}

/// One confirmation dialog. Returns true only when the user pressed the destructive action.
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
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Standard width for a short form field in a desktop dialog.
const double desktopFormFieldWidth = 380;
