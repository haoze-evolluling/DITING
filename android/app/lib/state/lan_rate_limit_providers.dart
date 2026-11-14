/// N9 state: LAN client rate limiting for the standalone DNS server.
library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LanRateLimitSettings {
  const LanRateLimitSettings({
    required this.enabled,
    required this.rate,
    required this.burst,
    required this.ipv4Prefix,
    required this.ipv6Prefix,
    required this.exemptCsv,
  });

  final bool enabled;
  final int rate;
  final int burst;
  final int ipv4Prefix;
  final int ipv6Prefix;
  final String exemptCsv;

  LanRateLimitSettings copyWith({
    bool? enabled,
    int? rate,
    int? burst,
    int? ipv4Prefix,
    int? ipv6Prefix,
    String? exemptCsv,
  }) => LanRateLimitSettings(
    enabled: enabled ?? this.enabled,
    rate: rate ?? this.rate,
    burst: burst ?? this.burst,
    ipv4Prefix: ipv4Prefix ?? this.ipv4Prefix,
    ipv6Prefix: ipv6Prefix ?? this.ipv6Prefix,
    exemptCsv: exemptCsv ?? this.exemptCsv,
  );
}

class LanRateLimitNotifier extends Notifier<LanRateLimitSettings> {
  @override
  LanRateLimitSettings build() {
    final settings = ref.read(legacySettingsProvider);
    final rate = settings.lanRateLimitRate;
    final burst = settings.lanRateLimitBurst;
    final ipv4 = settings.lanRateLimitIpv4Prefix;
    final ipv6 = settings.lanRateLimitIpv6Prefix;
    return LanRateLimitSettings(
      enabled: settings.lanRateLimitEnabled,
      rate: rate <= 0 ? 50 : rate,
      burst: burst <= 0 ? 100 : burst,
      ipv4Prefix: ipv4 <= 0 ? 32 : ipv4,
      ipv6Prefix: ipv6 <= 0 ? 128 : ipv6,
      exemptCsv: settings.lanRateLimitExemptCsv,
    );
  }

  void setEnabled(bool value) {
    ref.read(legacySettingsProvider).setLanRateLimitEnabled(value);
    state = state.copyWith(enabled: value);
  }

  void setRate(int value) {
    ref.read(legacySettingsProvider).setLanRateLimitRate(value);
    state = state.copyWith(rate: value);
  }

  void setBurst(int value) {
    ref.read(legacySettingsProvider).setLanRateLimitBurst(value);
    state = state.copyWith(burst: value);
  }

  void setIpv4Prefix(int value) {
    ref.read(legacySettingsProvider).setLanRateLimitIpv4Prefix(value);
    state = state.copyWith(ipv4Prefix: value);
  }

  void setIpv6Prefix(int value) {
    ref.read(legacySettingsProvider).setLanRateLimitIpv6Prefix(value);
    state = state.copyWith(ipv6Prefix: value);
  }

  void setExemptCsv(String value) {
    ref.read(legacySettingsProvider).setLanRateLimitExemptCsv(value);
    state = state.copyWith(exemptCsv: value);
  }
}

final lanRateLimitProvider =
    NotifierProvider<LanRateLimitNotifier, LanRateLimitSettings>(
      LanRateLimitNotifier.new,
    );
