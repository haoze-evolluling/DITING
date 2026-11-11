/// Work mode, power state, provider selection and server mode.
library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'dart:async';

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/notifications/notification_status_text.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/power_state.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:diting_android/data/vpn/power_state.dart';
export 'package:diting_android/state/provider_catalog_providers.dart';

part 'work_mode_power.dart';

/// The three work modes: `normal` (full-tunnel Go), `server` (DNS-only LAN), `express` (narrow
/// Kotlin route).
enum AppWorkMode {
  normal('normal'),
  server('dns'),
  express('express');

  const AppWorkMode(this.storageValue);

  String title(AppL10n l10n) => switch (this) {
    AppWorkMode.normal => l10n.workModeNormalTitle,
    AppWorkMode.server => l10n.workModeServerTitle,
    AppWorkMode.express => l10n.workModeExpressTitle,
  };

  String badge(AppL10n l10n) => switch (this) {
    AppWorkMode.normal => l10n.workModeNormalBadge,
    AppWorkMode.server => l10n.workModeServerBadge,
    AppWorkMode.express => l10n.workModeExpressBadge,
  };

  String summary(AppL10n l10n) => switch (this) {
    AppWorkMode.normal => l10n.workModeNormalSummary,
    AppWorkMode.server => l10n.workModeServerSummary,
    AppWorkMode.express => l10n.workModeExpressSummary,
  };

  /// Persisted legacy `app_work_mode` value; server mode is still stored as `dns`.
  final String storageValue;

  static AppWorkMode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => normal,
  );
}

/// Power state machine; the error state is server-mode only.
/// The enum lives in `data/vpn/power_state.dart` so UI-only consumers (desktop) can import it
/// without the VPN channel; this library re-exports it.
/// Work mode and power state share a notifier: switching mode stops the other service.
class WorkModeNotifier extends Notifier<AppWorkMode> {
  @override
  AppWorkMode build() => AppWorkMode.fromStorageValue(
    ref.read(legacySettingsProvider).workModeRaw,
  );

  void select(AppWorkMode mode) {
    final previous = state;
    // Stop before publishing: the channel is picked from the current mode.
    if (previous != mode) {
      final power = ref.read(powerProvider);
      if (power.isRunning || power == PowerState.starting) {
        unawaited(ref.read(powerProvider.notifier).stop());
      }
    }
    // Persist, then bump, then publish: the dataset-aware settings view has to point at the new
    // mode's container by the time dependents rebuild.
    ref.read(legacySettingsProvider).setWorkModeRaw(mode.storageValue);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
    state = mode;
  }
}

final workModeProvider = NotifierProvider<WorkModeNotifier, AppWorkMode>(
  WorkModeNotifier.new,
);

/// Real normal-mode tunnel control; tests override it with a fake.
final vpnControllerProvider = Provider<VpnController>(
  (ref) => MethodChannelVpnController(),
);

/// Express mode uses the same contract on its own channel.
final expressVpnControllerProvider = Provider<VpnController>(
  (ref) =>
      MethodChannelVpnController(channel: MethodChannel(expressVpnChannelName)),
);

/// Service statistics shared by server mode and the log page.
class ServiceStatsNotifier extends Notifier<ServiceStats> {
  static const zero = ServiceStats(
    queries: 0,
    cacheHits: 0,
    blocked: 0,
    averageLatencyMs: 0,
    uptime: Duration.zero,
  );

  /// Origin of the uptime figure. Preference order: the native start timestamp (survives a
  /// recreated UI process), then the local clock from [markStarted].
  DateTime? _startedAt;

  @override
  ServiceStats build() => zero;

  void reset() {
    _startedAt = null;
    state = zero;
  }

  /// Called when a tunnel reports `running` for the first time.
  void markStarted() {
    _startedAt = DateTime.now();
    state = zero;
  }

  /// Replaces the mock counters with the Go engine's real ones.
  ///
  /// [startedAt] is the service's own start time. It wins over the locally observed one so a
  /// recreated UI process shows the real uptime instead of starting again from zero.
  ///
  /// [ownsStats] is false when the caller's plane is not the one the current work mode drives.
  /// Only one data plane can run at a time, so a non-owner always reports `running: false`; acting
  /// on that would zero the live uptime the owner just published (the status card flashed `0秒`
  /// for a second whenever both notifiers re-synced on resume).
  void applyNative(
    Map<String, Object?> stats, {
    required bool running,
    bool ownsStats = true,
    DateTime? startedAt,
  }) {
    if (!ownsStats) return;
    if (!running) {
      reset();
      return;
    }
    _startedAt = startedAt ?? _startedAt ?? DateTime.now();
    int read(String key) => (stats[key] as num?)?.toInt() ?? 0;
    final elapsed = DateTime.now().difference(_startedAt!);
    state = ServiceStats(
      queries: read('queries'),
      cacheHits: read('cacheHits'),
      blocked: read('blocked'),
      averageLatencyMs: 0,
      // A device clock that moved backwards must not show a negative duration.
      uptime: elapsed.isNegative ? Duration.zero : elapsed,
    );
  }

  void bump() {
    state = ServiceStats(
      queries: state.queries + 1,
      cacheHits: state.cacheHits + (state.queries.isEven ? 1 : 0),
      blocked: state.blocked,
      averageLatencyMs: state.averageLatencyMs,
      uptime: state.uptime + const Duration(seconds: 1),
    );
  }

  /// Advances the uptime off the start clock without a platform round trip, so the status card
  /// ticks every second while the native counters are polled less often.
  void refreshUptime() {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    final uptime = elapsed.isNegative ? Duration.zero : elapsed;
    if (uptime.inSeconds == state.uptime.inSeconds) return;
    state = ServiceStats(
      queries: state.queries,
      cacheHits: state.cacheHits,
      blocked: state.blocked,
      averageLatencyMs: state.averageLatencyMs,
      uptime: uptime,
    );
  }
}

final serviceStatsProvider =
    NotifierProvider<ServiceStatsNotifier, ServiceStats>(
      ServiceStatsNotifier.new,
    );

/// Whether the home page has picked a work mode (onboarding marker).
class WorkModeSelectedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(legacySettingsProvider).workModeSelected;

  void markSelected() {
    state = true;
    ref.read(legacySettingsProvider).setWorkModeSelected(true);
  }

  void reset() {
    state = false;
    ref.read(legacySettingsProvider).clearWorkModeSelection();
  }
}

final workModeSelectedProvider =
    NotifierProvider<WorkModeSelectedNotifier, bool>(
      WorkModeSelectedNotifier.new,
    );

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(legacySettingsProvider).modeOnboardingCompleted;

  void complete() {
    state = true;
    ref.read(legacySettingsProvider).setModeOnboardingCompleted(true);
  }

  void reset() {
    state = false;
    ref.read(legacySettingsProvider).setModeOnboardingCompleted(false);
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);

/// Provider summary text for the home `resolutionMode` (upstream `raceProviderSummary`).
String raceProviderSummary(Set<String> ids) =>
    summaryOfProviders(ids, defaultProviderCatalog());

/// Endpoint text; must use `.label`, since `toString()` leaks `ProviderProtocol.doh`.
String providerEndpointOf(String id) =>
    endpointOfProvider(id, defaultProviderCatalog());

/// Convenience read of the resolution mode from `appearance_providers.dart`.
ResolutionMode resolutionModeOf(Ref ref) => ref.read(resolutionModeProvider);
