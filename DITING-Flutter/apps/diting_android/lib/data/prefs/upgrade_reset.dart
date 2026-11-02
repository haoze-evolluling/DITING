/// One-time resets that run on the first launch after an upgrade.
///
/// A feature whose stored state should go back to defaults once (a new default layout, a changed
/// meaning of an old key) adds an [UpgradeReset] to the registry instead of carrying its own
/// version counter. [runUpgradeResets] runs every entry whose [UpgradeReset.id] has not been
/// recorded yet, then records it, so each reset happens exactly once per install, even when the
/// user skips versions. Ids are part of the upgrade contract: never rename or reuse one.
library;

import 'dart:convert';

import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter/foundation.dart';

@immutable
class UpgradeReset {
  const UpgradeReset({
    required this.id,
    required this.since,
    required this.apply,
  });

  /// Removes [keys] from [container], the usual reset: every reader treats a missing key as
  /// "never changed" and falls back to its built-in default.
  UpgradeReset.prefs({
    required String id,
    required String since,
    required String container,
    required List<String> keys,
  }) : this(
         id: id,
         since: since,
         apply: (store) {
           for (final key in keys) {
             store.remove(container, key);
           }
         },
       );

  /// Stable, unique key recorded once the reset ran, e.g. `2.2.1_log_dashboard_layout`.
  final String id;

  /// Version that introduced the reset; documentation only, the run is keyed by [id].
  final String since;

  /// Runs before the first frame, before any provider reads the store.
  final void Function(LegacyPrefsStore store) apply;
}

/// Ids of resets that already ran, kept in the UI container with the other app-level flags.
const upgradeResetsAppliedKey = 'upgrade_resets_applied';

/// Runs the pending entries of [resets] in order and records each id. A reset that throws is
/// logged and left unrecorded, so it retries on the next launch instead of blocking startup.
/// Returns the ids that ran.
List<String> runUpgradeResets(
  LegacyPrefsStore store,
  List<UpgradeReset> resets,
) {
  final applied = _appliedIds(store);
  final ran = <String>[];
  for (final reset in resets) {
    if (applied.contains(reset.id)) continue;
    try {
      reset.apply(store);
    } catch (error) {
      debugPrint('upgrade reset ${reset.id} failed: $error');
      continue;
    }
    applied.add(reset.id);
    ran.add(reset.id);
  }
  if (ran.isNotEmpty) {
    store.putStringSet(
      LegacySettings.uiContainer,
      upgradeResetsAppliedKey,
      applied,
    );
  }
  return ran;
}

/// The platform store returns a string set as a list; a JSON string is accepted as well.
Set<String> _appliedIds(LegacyPrefsStore store) {
  Object? value = store.read(
    LegacySettings.uiContainer,
    upgradeResetsAppliedKey,
  );
  if (value is String) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return {};
    }
  }
  if (value is! List) return {};
  return {
    for (final item in value)
      if (item is String && item.isNotEmpty) item,
  };
}
