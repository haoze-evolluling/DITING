library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectionRateLimitSettings {
  const ConnectionRateLimitSettings({
    required this.enabled,
    required this.rate,
    required this.burst,
  });

  static const minRate = 5;
  static const maxRate = 1000;
  static const minBurst = 10;
  static const maxBurst = 2000;

  final bool enabled;
  final int rate;
  final int burst;

  ConnectionRateLimitSettings copyWith({
    bool? enabled,
    int? rate,
    int? burst,
  }) => ConnectionRateLimitSettings(
    enabled: enabled ?? this.enabled,
    rate: rate ?? this.rate,
    burst: burst ?? this.burst,
  );
}

class ConnectionRateLimitNotifier
    extends Notifier<ConnectionRateLimitSettings> {
  @override
  ConnectionRateLimitSettings build() {
    final settings = ref.read(legacySettingsProvider);
    return ConnectionRateLimitSettings(
      enabled: settings.connectionRateLimitEnabled,
      rate: settings.connectionRateLimitRate.clamp(
        ConnectionRateLimitSettings.minRate,
        ConnectionRateLimitSettings.maxRate,
      ),
      burst: settings.connectionRateLimitBurst.clamp(
        ConnectionRateLimitSettings.minBurst,
        ConnectionRateLimitSettings.maxBurst,
      ),
    );
  }

  void setEnabled(bool value) {
    ref.read(legacySettingsProvider).setConnectionRateLimitEnabled(value);
    state = state.copyWith(enabled: value);
  }

  void setRate(int value) {
    final clamped = value.clamp(
      ConnectionRateLimitSettings.minRate,
      ConnectionRateLimitSettings.maxRate,
    );
    ref.read(legacySettingsProvider).setConnectionRateLimitRate(clamped);
    state = state.copyWith(rate: clamped);
  }

  void setBurst(int value) {
    final clamped = value.clamp(
      ConnectionRateLimitSettings.minBurst,
      ConnectionRateLimitSettings.maxBurst,
    );
    ref.read(legacySettingsProvider).setConnectionRateLimitBurst(clamped);
    state = state.copyWith(burst: clamped);
  }
}

final connectionRateLimitProvider =
    NotifierProvider<ConnectionRateLimitNotifier, ConnectionRateLimitSettings>(
      ConnectionRateLimitNotifier.new,
    );
