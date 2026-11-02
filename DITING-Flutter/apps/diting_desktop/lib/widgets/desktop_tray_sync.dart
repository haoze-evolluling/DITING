/// Keeps the native notification-area menu in step with the app locale.
///
/// Sits inside the app's [MaterialApp.builder], i.e. under the localization
/// scope, so `AppL10n.of(context)` resolves the same locale the pages use. It
/// renders nothing and is a no-op outside the Windows window (the same bundle
/// is also served to browsers as the LAN web console).
library;

import 'dart:async';

import 'package:diting_desktop/data/host/desktop_tray.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

class DesktopTraySync extends StatefulWidget {
  const DesktopTraySync({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopTraySync> createState() => _DesktopTraySyncState();
}

class _DesktopTraySyncState extends State<DesktopTraySync> {
  final _tray = const DesktopTray();
  DesktopTrayLabels? _sent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!DesktopTray.isSupported) return;
    // The locale changed (or this is the first build): re-label the tray once.
    final labels = DesktopTrayLabels.of(AppL10n.of(context));
    if (labels == _sent) return;
    _sent = labels;
    unawaited(_tray.configure(labels));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
