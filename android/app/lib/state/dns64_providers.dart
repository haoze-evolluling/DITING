/// N8 state: the DNS64 synthesis switch, backed by the legacy settings store.
library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Dns64SettingsNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(legacySettingsProvider).dns64Enabled;

  void setEnabled(bool value) {
    ref.read(legacySettingsProvider).setDns64Enabled(value);
    state = value;
  }
}

final dns64EnabledProvider = NotifierProvider<Dns64SettingsNotifier, bool>(
  Dns64SettingsNotifier.new,
);
