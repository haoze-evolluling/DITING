import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:diting_android/data/prefs/legacy_settings.dart';

final legacyPrefsStoreProvider = Provider<LegacyPrefsStore>(
  (ref) => MemoryLegacyPrefsStore(),
);

class LegacySettingsRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final legacySettingsRevisionProvider =
    NotifierProvider<LegacySettingsRevision, int>(LegacySettingsRevision.new);

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
