library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

Future<void> savePrivacySetting(
  BuildContext context,
  WidgetRef ref,
  Future<Object?> Function() write,
  String success,
) async {
  final l10n = context.l10n;
  final error = await write();
  if (!context.mounted) return;
  showDesktopMessage(
    context,
    error == null ? success : l10n.desktopPrivacySaveFailed('$error'),
  );
}
