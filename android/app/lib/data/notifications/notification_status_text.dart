library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/prefs/legacy_settings.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';

String _modeLabel(String mode, AppL10n l10n) => switch (mode) {
  'single' => l10n.notifModeSingle,
  'smart_prediction' => l10n.notifModeSmart,
  'parallel_race' => l10n.notifModeParallel,
  'primary_backup' => l10n.notifModeBackup,
  _ => mode,
};

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
