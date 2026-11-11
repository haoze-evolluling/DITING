/// Windows notification-area integration for the desktop window.
///
/// The icon itself lives in native code (`windows/runner/tray`): the menu, the
/// SCM and registry calls behind it, and the balloons. That is deliberate - a
/// `--minimized` sign-in start has no Flutter frame yet, and the old Wails
/// desktop's tray behaved the same way. The only thing that has to come from
/// Dart is localization, so the menu follows the app locale instead of being
/// hard-coded to Chinese.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The tray strings of one locale, under the keys the runner reads in
/// `tray_channel.cpp`.
@immutable
class DesktopTrayLabels {
  const DesktopTrayLabels._(this.values);

  /// Maps the shared ARB resources onto the runner's label keys.
  factory DesktopTrayLabels.of(AppL10n l10n) => DesktopTrayLabels._({
    'tooltip': l10n.desktopTrayTooltip,
    'open_window': l10n.desktopTrayOpenWindow,
    'hide_window': l10n.desktopTrayHideWindow,
    'auto_start': l10n.desktopTrayAutoStart,
    'service_running': l10n.desktopTrayServiceRunning,
    'service_stopped': l10n.desktopTrayServiceStopped,
    'service_unknown': l10n.desktopTrayServiceUnknown,
    'service_start': l10n.desktopTrayServiceStart,
    'service_stop': l10n.desktopTrayServiceStop,
    'service_restart': l10n.desktopTrayServiceRestart,
    'quit': l10n.desktopTrayQuit,
    'balloon_service_title': l10n.desktopTrayBalloonServiceTitle,
    'balloon_service_started': l10n.desktopTrayBalloonServiceStarted,
    'balloon_service_stopped': l10n.desktopTrayBalloonServiceStopped,
    'balloon_service_restarted': l10n.desktopTrayBalloonServiceRestarted,
    'balloon_autostart_title': l10n.desktopTrayBalloonAutoStartTitle,
    'balloon_autostart_on': l10n.desktopTrayBalloonAutoStartOn,
    'balloon_autostart_off': l10n.desktopTrayBalloonAutoStartOff,
    'balloon_failed': l10n.desktopTrayBalloonFailedPrefix,
    'balloon_minimized_body': l10n.desktopTrayBalloonMinimized,
  });

  final Map<String, String> values;

  @override
  bool operator ==(Object other) =>
      other is DesktopTrayLabels && mapEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(
    values.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// The `diting/tray` channel. Everything it does is best effort: the tray is a
/// convenience, so a missing plugin (web console, older runner) must never
/// surface as an app error.
class DesktopTray {
  const DesktopTray({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('diting/tray');

  final MethodChannel _channel;

  /// False on the web console, where the same bundle runs but there is no tray.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> configure(DesktopTrayLabels labels) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('configure', labels.values);
    } on MissingPluginException {
      // Runner without the tray build: keep starting the app.
    } on PlatformException {
      // A rejected label update only leaves the previous locale in place.
    }
  }
}
