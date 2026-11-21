library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'dart:async';

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/notifications/notification_status_text.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/power_state.dart';
import 'package:diting_android/data/vpn/root_dns_bridge.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:diting_android/data/vpn/power_state.dart';
export 'package:diting_android/state/provider_catalog_providers.dart';

part 'work_mode_power.dart';

enum AppWorkMode {
  normal('normal'),
  express('express'),
  server('server');

  const AppWorkMode(this.storageValue);

  String title(AppL10n l10n) => switch (this) {
    AppWorkMode.normal => l10n.workModeNormalTitle,
    AppWorkMode.express => l10n.workModeExpressTitle,
    AppWorkMode.server => l10n.workModeServerTitle,
  };

  String badge(AppL10n l10n) => switch (this) {
    AppWorkMode.normal => l10n.workModeNormalBadge,
    AppWorkMode.express => l10n.workModeExpressBadge,
    AppWorkMode.server => l10n.workModeServerBadge,
  };

  String summary(AppL10n l10n) => switch (this) {
    AppWorkMode.normal => l10n.workModeNormalSummary,
    AppWorkMode.express => l10n.workModeExpressSummary,
    AppWorkMode.server => l10n.workModeServerSummary,
  };

  final String storageValue;

  /// 是否走本地全隧道数据面（普通模式与极速模式一致，只有服务器模式例外）。
  ///
  /// 流量统计、HTTP 记录、分应用管控、HTTPS 检查等能力都依赖全隧道，
  /// 因此这些功能的可用性判断一律用它，而不是逐个比较 `AppWorkMode.normal`。
  bool get hasTunnelFeatures => this != AppWorkMode.server;

  static AppWorkMode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => normal,
  );
}

class WorkModeNotifier extends Notifier<AppWorkMode> {
  @override
  AppWorkMode build() => AppWorkMode.fromStorageValue(
    ref.read(legacySettingsProvider).workModeRaw,
  );

  void select(AppWorkMode mode) {
    final previous = state;
    if (previous != mode) {
      final power = ref.read(powerProvider);
      if (power.isRunning || power == PowerState.starting) {
        unawaited(ref.read(powerProvider.notifier).stop());
      }
      if (previous == AppWorkMode.server) {
        unawaited(ref.read(serverClientProvider).stop());
      }
    }
    ref.read(legacySettingsProvider).setWorkModeRaw(mode.storageValue);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
    state = mode;
  }
}

final workModeProvider = NotifierProvider<WorkModeNotifier, AppWorkMode>(
  WorkModeNotifier.new,
);

final vpnControllerProvider = Provider<VpnController>(
  (ref) => MethodChannelVpnController(),
);

final expressVpnControllerProvider = Provider<VpnController>(
  (ref) =>
      MethodChannelVpnController(channel: MethodChannel(expressVpnChannelName)),
);

final rootDnsControllerProvider = Provider<VpnController>(
  (ref) => MethodChannelRootDnsController(),
);

class RootDnsTakeoverNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(legacySettingsProvider).rootDnsTakeoverEnabled;

  Future<void> set(bool value) async {
    if (value == state) return;
    if (ref.read(workModeProvider) == AppWorkMode.normal) {
      final power = ref.read(powerProvider);
      if (power.isRunning || power.isBusy) {
        await ref.read(powerProvider.notifier).stop();
      }
    }
    state = value;
    ref.read(legacySettingsProvider).setRootDnsTakeoverEnabled(value);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  Future<void> toggle() => set(!state);
}

final rootDnsTakeoverProvider = NotifierProvider<RootDnsTakeoverNotifier, bool>(
  RootDnsTakeoverNotifier.new,
);

class ServiceStatsNotifier extends Notifier<ServiceStats> {
  static const zero = ServiceStats(
    queries: 0,
    cacheHits: 0,
    blocked: 0,
    averageLatencyMs: 0,
    uptime: Duration.zero,
  );

  DateTime? _startedAt;

  @override
  ServiceStats build() => zero;

  void reset() {
    _startedAt = null;
    state = zero;
  }

  void markStarted() {
    _startedAt = DateTime.now();
    state = zero;
  }

  void applyNative(
    Map<String, Object?> stats, {
    required bool running,
    DateTime? startedAt,
  }) {
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

String raceProviderSummary(Set<String> ids) =>
    summaryOfProviders(ids, defaultProviderCatalog());

String providerEndpointOf(String id) =>
    endpointOfProvider(id, defaultProviderCatalog());

ResolutionMode resolutionModeOf(Ref ref) => ref.read(resolutionModeProvider);
