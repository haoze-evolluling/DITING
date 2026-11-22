library;

import 'dart:convert';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/dns_latency_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const latencyTestProviderIdsKey = 'latency_test_provider_ids';

const raceTestDomainKey = 'race_test_domain';

const defaultRaceTestDomain = 'mihoyo.com';

const latencyTestAttempts = 3;

final dnsLatencyRunnerProvider = Provider<DnsLatencyRunner>(
  (ref) => const UnavailableDnsLatencyRunner(),
);

final latencyTestAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(dnsLatencyRunnerProvider).checkAvailable(),
);

final latencyTestCatalogProvider = Provider<List<DnsLatencyProviderSpec>>((
  ref,
) {
  final settings = ref.watch(legacySettingsProvider);
  final entries = [
    ...defaultDnsProviders(currentL10n),
    ...parseUserProviders(settings.userProvidersJson),
  ];
  return [for (final entry in entries) latencySpecOf(entry)];
});

DnsLatencyProviderSpec latencySpecOf(DnsProviderEntry entry) {
  final protocol = switch (entry.protocol) {
    DnsProtocol.dns => DnsLatencyProtocol.dns,
    DnsProtocol.doh => DnsLatencyProtocol.doh,
    DnsProtocol.dot => DnsLatencyProtocol.dot,
  };
  final host = entry.host.isNotEmpty
      ? entry.host
      : Uri.tryParse(entry.url)?.host ?? '';
  final port = switch (protocol) {
    DnsLatencyProtocol.doh => 443,
    DnsLatencyProtocol.dot => entry.port == 0 ? 853 : entry.port,
    DnsLatencyProtocol.dns => entry.port == 0 ? 53 : entry.port,
  };
  return DnsLatencyProviderSpec(
    id: entry.id,
    name: entry.name,
    host: host,
    port: port,
    protocol: protocol,
    url: entry.url,
  );
}

String latencyEndpointLabel(DnsLatencyProviderSpec spec) {
  if (spec.protocol == DnsLatencyProtocol.doh) {
    final url = spec.url.isNotEmpty
        ? spec.url
        : 'https://${spec.host}/dns-query';
    return '[${spec.protocol.label}] $url';
  }
  return '[${spec.protocol.label}] ${spec.host}:${spec.port}';
}

final latencyProvidersOfProtocolProvider =
    Provider.family<List<DnsLatencyProviderSpec>, DnsLatencyProtocol>((
      ref,
      protocol,
    ) {
      return [
        for (final spec in ref.watch(latencyTestCatalogProvider))
          if (spec.protocol == protocol) spec,
      ];
    });

final latencyTestProtocolsProvider = Provider<List<DnsLatencyProtocol>>((ref) {
  final present = {
    for (final spec in ref.watch(latencyTestCatalogProvider)) spec.protocol,
  };
  final ordered = [
    for (final protocol in DnsLatencyProtocol.values)
      if (present.contains(protocol)) protocol,
  ];
  return ordered.isEmpty ? DnsLatencyProtocol.values : ordered;
});

class LatencySelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final settings = ref.watch(legacySettingsProvider);
    final known = {
      for (final spec in ref.watch(latencyTestCatalogProvider)) spec.id,
    };
    return {
      for (final id in _readIds(settings))
        if (known.contains(id)) id,
    };
  }

  void toggle(String id) {
    final next = {...state};
    if (!next.remove(id)) {
      next.add(id);
    }
    _persist(next);
    state = next;
  }

  static List<String> _readIds(LegacySettings settings) {
    final raw = settings.rawValue(latencyTestProviderIdsKey);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      ];
    } on FormatException {
      return const [];
    }
  }

  void _persist(Set<String> ids) {
    final settings = ref.read(legacySettingsProvider);
    ref
        .read(legacyPrefsStoreProvider)
        .putString(
          settings.dnsContainer,
          latencyTestProviderIdsKey,
          jsonEncode(ids.toList()..sort()),
        );
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final latencySelectionProvider =
    NotifierProvider<LatencySelectionNotifier, Set<String>>(
      LatencySelectionNotifier.new,
    );

class LatencyProtocolNotifier extends Notifier<DnsLatencyProtocol> {
  @override
  DnsLatencyProtocol build() {
    final available = ref.watch(latencyTestProtocolsProvider);
    return available.first;
  }

  void select(DnsLatencyProtocol protocol) {
    if (state == protocol) return;
    if (!ref.read(latencyTestProtocolsProvider).contains(protocol)) return;
    state = protocol;
  }
}

final latencyProtocolProvider =
    NotifierProvider<LatencyProtocolNotifier, DnsLatencyProtocol>(
      LatencyProtocolNotifier.new,
    );

class LatencyDomainNotifier extends Notifier<String> {
  @override
  String build() {
    final settings = ref.watch(legacySettingsProvider);
    final raw = settings.rawValue(raceTestDomainKey);
    final value = raw is String ? raw.trim() : '';
    return value.isEmpty ? defaultRaceTestDomain : value;
  }

  void setDomain(String value) {
    final trimmed = value.replaceAll(RegExp(r'\s'), '');
    if (trimmed == state) return;
    state = trimmed;
    _persist(trimmed);
  }

  void _persist(String value) {
    final settings = ref.read(legacySettingsProvider);
    ref
        .read(legacyPrefsStoreProvider)
        .putString(
          settings.dnsContainer,
          raceTestDomainKey,
          value.isEmpty ? defaultRaceTestDomain : value,
        );
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final latencyDomainProvider = NotifierProvider<LatencyDomainNotifier, String>(
  LatencyDomainNotifier.new,
);

class LatencyTestState {
  const LatencyTestState({
    this.running = false,
    this.results = const [],
    this.error,
    this.unavailable = false,
  });

  final bool running;

  final List<DnsLatencySample> results;

  final String? error;

  final bool unavailable;
}

class LatencyTestNotifier extends Notifier<LatencyTestState> {
  @override
  LatencyTestState build() {
    final available = ref.watch(latencyTestAvailableProvider);
    if (available.value == false) {
      return const LatencyTestState(unavailable: true);
    }
    return const LatencyTestState();
  }

  Future<void> run() async {
    if (state.running) return;
    final selected = ref.read(latencySelectionProvider);
    final providers = [
      for (final spec in ref.read(latencyTestCatalogProvider))
        if (selected.contains(spec.id)) spec,
    ];
    if (providers.isEmpty) {
      _fail(currentL10n.speedTestSelectProvider);
      return;
    }
    final domain = ref.read(latencyDomainProvider);
    if (domain.isEmpty) {
      _fail(currentL10n.speedTestEmptyDomain);
      return;
    }
    state = LatencyTestState(running: true, results: const []);
    try {
      final results = await ref
          .read(dnsLatencyRunnerProvider)
          .probe(
            providers: providers,
            domain: domain,
            attempts: latencyTestAttempts,
          );
      state = LatencyTestState(results: sortLatencySamples(results));
    } on DnsLatencyUnavailable catch (error) {
      state = LatencyTestState(unavailable: true, error: error.message);
    }
  }

  void _fail(String message) {
    state = LatencyTestState(
      results: state.results,
      unavailable: state.unavailable,
      error: message,
    );
  }

  void clearError() {
    if (state.error == null) return;
    state = LatencyTestState(
      results: state.results,
      unavailable: state.unavailable,
    );
  }
}

final latencyTestProvider =
    NotifierProvider<LatencyTestNotifier, LatencyTestState>(
      LatencyTestNotifier.new,
    );

List<DnsLatencySample> sortLatencySamples(List<DnsLatencySample> samples) {
  final sorted = [...samples];
  sorted.sort((a, b) {
    if (a.success != b.success) return a.success ? -1 : 1;
    if (a.success) {
      final byElapsed = a.elapsedMs.compareTo(b.elapsedMs);
      if (byElapsed != 0) return byElapsed;
    }
    final byCount = b.successCount.compareTo(a.successCount);
    if (byCount != 0) return byCount;
    return a.providerName.compareTo(b.providerName);
  });
  return sorted;
}

int latencyBarMax(List<DnsLatencySample> samples) {
  var max = 0;
  for (final sample in samples) {
    if (sample.success && sample.elapsedMs > max) max = sample.elapsedMs;
  }
  return max;
}
