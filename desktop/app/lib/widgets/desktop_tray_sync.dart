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
    final labels = DesktopTrayLabels.of(AppL10n.of(context));
    if (labels == _sent) return;
    _sent = labels;
    unawaited(_tray.configure(labels));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
