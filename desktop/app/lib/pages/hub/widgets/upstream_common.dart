library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

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
