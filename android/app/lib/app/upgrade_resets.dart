/// Registry of one-time upgrade resets; see `upgrade_reset.dart` for the mechanism.
///
/// To add one: append an entry with a new id (`<version>_<what>`) and the version that ships
/// it. Prefer [UpgradeReset.prefs] so the feature falls back to its own defaults; use the plain
/// constructor only when the reset has to rewrite a value instead of dropping it. Keep shipped
/// entries: removing one lets nothing break, but the list doubles as the reset history.
library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/prefs/upgrade_reset.dart';
import 'package:diting_shared/state/settings_providers.dart';

export 'package:diting_android/data/prefs/upgrade_reset.dart';

final upgradeResets = <UpgradeReset>[
  // The log dashboard got a new default card order per log mode; saved boards go back to it.
  UpgradeReset.prefs(
    id: '2.2.1_log_dashboard_layout',
    since: '2.2.1',
    container: LegacySettings.uiContainer,
    keys: [
      for (final mode in LegacyLogMode.values)
        logDashboardWidgetOrderKey(mode.storageValue),
    ],
  ),
];
