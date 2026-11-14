/// U10 state: the privacy suite's two DNS switches, backed by the legacy settings store.
library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrivacySettings {
  const PrivacySettings({
    required this.blockHttpsSvcb,
    required this.rebindingProtection,
  });

  final bool blockHttpsSvcb;
  final bool rebindingProtection;

  PrivacySettings copyWith({bool? blockHttpsSvcb, bool? rebindingProtection}) =>
      PrivacySettings(
        blockHttpsSvcb: blockHttpsSvcb ?? this.blockHttpsSvcb,
        rebindingProtection: rebindingProtection ?? this.rebindingProtection,
      );
}

class PrivacySettingsNotifier extends Notifier<PrivacySettings> {
  @override
  PrivacySettings build() {
    final settings = ref.read(legacySettingsProvider);
    return PrivacySettings(
      blockHttpsSvcb: settings.blockHttpsSvcbRecordTypes,
      rebindingProtection: settings.dnsRebindingProtection,
    );
  }

  void setBlockHttpsSvcb(bool value) {
    ref.read(legacySettingsProvider).setBlockHttpsSvcbRecordTypes(value);
    state = state.copyWith(blockHttpsSvcb: value);
  }

  void setRebindingProtection(bool value) {
    ref.read(legacySettingsProvider).setDnsRebindingProtection(value);
    state = state.copyWith(rebindingProtection: value);
  }
}

final privacySettingsProvider =
    NotifierProvider<PrivacySettingsNotifier, PrivacySettings>(
      PrivacySettingsNotifier.new,
    );
