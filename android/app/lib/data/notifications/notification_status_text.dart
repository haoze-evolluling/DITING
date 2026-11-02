/// Notification bodies for the three data planes.
///
/// The foreground services only see the config JSON, which carries provider ids but no display
/// names, so Dart composes the body here and stores it in `notification_settings_prefs`; a
/// user-defined text still wins natively.
///
/// Every mode shares one grammar, `运行中 · <上游>`, and carries its mode name in the title:
/// `运行中 · 阿里云`, `运行中 · [最快响应] 3 个服务商`, `运行中 · 阿里云 · 端口 1053`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/data/server/dns_server_config.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';

/// Legacy wording of the resolution modes; shorter UI labels would not say what is racing.
String _modeLabel(String mode, AppL10n l10n) => switch (mode) {
  'single' => l10n.notifModeSingle,
  'smart_prediction' => l10n.notifModeSmart,
  'parallel_race' => l10n.notifModeParallel,
  'primary_backup' => l10n.notifModeBackup,
  _ => mode,
};

/// `运行中 · [最快响应] 3 个服务商` / `运行中 · 阿里云` / `运行中`.
///
/// Normal and express share this shape; the mode itself is the notification title.
String defaultRunningNotificationText(LegacySettings settings) {
  final config = buildDnsConfig(settings);
  final providers = config.providers;
  if (providers.length > 1) {
    final mode = _modeLabel(config.mode, currentL10n);
    return currentL10n.notifRunningMode(mode, providers.length);
  }
  if (providers.isNotEmpty) {
    return currentL10n.notifRunningProvider(providers.first.name);
  }
  return currentL10n.stateRunning;
}

/// `运行中 · 阿里云 · 端口 1053`: the upstream name plus the listen port, which is not 53 here.
String defaultServerNotificationText(LegacySettings settings) {
  final config = buildServerDnsConfig(settings);
  return currentL10n.notifRunningServer(config.upstream.name, config.port);
}
