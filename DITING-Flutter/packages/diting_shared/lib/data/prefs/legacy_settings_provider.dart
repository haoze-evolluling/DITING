import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Re-exported so a page reading [legacySettingsProvider] gets the type and its extensions at once.
export 'package:diting_shared/data/prefs/legacy_settings.dart';

/// Overridden with the Android snapshot in `main()`; the memory default lets tests and non-Android
/// hosts start with the documented defaults.
final legacyPrefsStoreProvider = Provider<LegacyPrefsStore>(
  (ref) => MemoryLegacyPrefsStore(),
);

/// Bumped after any write through [LegacySettings]; writes are fire-and-forget, so pages must
/// depend on it.
class LegacySettingsRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final legacySettingsRevisionProvider =
    NotifierProvider<LegacySettingsRevision, int>(LegacySettingsRevision.new);

/// Active data set, derived from the persisted `app_work_mode`. It watches the write revision, so
/// `WorkModeNotifier` only has to persist the new mode for every dataset reader to follow.
class ActiveDataSet extends Notifier<DataSet> {
  @override
  DataSet build() {
    ref.watch(legacySettingsRevisionProvider);
    final store = ref.watch(legacyPrefsStoreProvider);
    return DataSet.fromWorkModeValue(LegacySettings(store).workModeRaw);
  }
}

final activeDataSetProvider = NotifierProvider<ActiveDataSet, DataSet>(
  ActiveDataSet.new,
);

/// DNS-domain settings of the active data set. UI keys stay global: only the dataset container
/// switches, so theme, background and notification settings never duplicate per mode.
final legacySettingsProvider = Provider<LegacySettings>((ref) {
  ref.watch(legacySettingsRevisionProvider);
  return LegacySettings(
    ref.watch(legacyPrefsStoreProvider),
    dnsContainer: ref.watch(activeDataSetProvider).prefsContainer,
  );
});

extension LegacySettingsWrite on WidgetRef {
  void writeSettings(void Function(LegacySettings settings) write) {
    write(read(legacySettingsProvider));
    read(legacySettingsRevisionProvider.notifier).bump();
  }
}
