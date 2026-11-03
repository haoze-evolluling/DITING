/// Provider catalog, selection and race lists; presets live in code, only custom providers and the
/// id lists persist.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/provider_store.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Presets only, for hosts without a prefs snapshot (tests, gallery).
List<MockProvider> defaultProviderCatalog() => [
  for (final provider in defaultDnsProviders(currentL10n))
    provider.toMock(latencyMs: -1, isPreset: true),
];

ProviderProtocol _protocolOf(DnsProtocol protocol) => switch (protocol) {
  DnsProtocol.dns => ProviderProtocol.dns,
  DnsProtocol.doh => ProviderProtocol.doh,
  DnsProtocol.dot => ProviderProtocol.dot,
};

/// The full catalog: 18 presets then custom providers in file order.
List<MockProvider> buildProviderCatalog(LegacySettings settings) {
  final latencies = settings.providerLatenciesMs;
  return [
    for (final provider in defaultDnsProviders(currentL10n))
      provider.toMock(latencyMs: latencies[provider.id] ?? -1, isPreset: true),
    for (final record in readUserProviders(settings))
      MockProvider(
        id: record.id,
        name: record.name,
        protocol: _protocolOf(record.protocol),
        address: record.address,
        latencyMs: latencies[record.id] ?? -1,
      ),
  ];
}

/// Endpoint text for one provider; `latencyMs < 0` means no measurement yet, so the UI renders a
/// dash.
String endpointOfProvider(String id, List<MockProvider> catalog) {
  final provider = catalog.firstWhere(
    (candidate) => candidate.id == id,
    orElse: () => catalog.first,
  );
  return '${provider.protocol.label} · ${provider.address}';
}

/// Same as [endpointOfProvider] but for callers holding only a container.
String providerEndpointFromCatalog(WidgetRef ref, String id) =>
    endpointOfProvider(id, ref.watch(dnsProviderCatalogProvider));

/// Display text for a provider's last measured latency.
String providerLatencyLabel(MockProvider provider) => provider.latencyMs < 0
    ? currentL10n.providerNotTested
    : currentL10n.providerLatencyValue(provider.latencyMs);

/// Names in the given order (the order the engine tries them); ids missing from the catalog are
/// skipped.
String summaryOfProviders(Set<String> ids, List<MockProvider> catalog) {
  final byId = {for (final provider in catalog) provider.id: provider};
  final names = [for (final id in ids) ?byId[id]?.name];
  if (names.isEmpty) {
    return currentL10n.providerNoProviderSelected;
  }
  if (names.length == 1) {
    return names.first;
  }
  return currentL10n.providerRaceSummaryNames(
    names.length,
    names.join(currentL10n.providerNamesSeparator),
  );
}

class ProviderCatalogNotifier extends Notifier<List<MockProvider>> {
  @override
  List<MockProvider> build() =>
      buildProviderCatalog(ref.watch(legacySettingsProvider));

  void _refresh() =>
      state = buildProviderCatalog(ref.read(legacySettingsProvider));

  /// Persists one custom provider; presets are read-only.
  void addCustom({
    required String name,
    required ProviderProtocol protocol,
    required String address,
  }) {
    addUserProvider(
      ref.read(legacySettingsProvider),
      name: name,
      protocol: _dnsProtocolOf(protocol),
      address: address,
    );
    _refresh();
  }

  void updateCustom({
    required String id,
    required String name,
    required ProviderProtocol protocol,
    required String address,
  }) {
    updateUserProvider(
      ref.read(legacySettingsProvider),
      id: id,
      name: name,
      protocol: _dnsProtocolOf(protocol),
      address: address,
    );
    _refresh();
    ref.invalidate(selectedProviderProvider);
    ref.invalidate(raceProvidersProvider);
  }

  void deleteCustom(String id) {
    deleteUserProvider(ref.read(legacySettingsProvider), id);
    _refresh();
    ref.invalidate(selectedProviderProvider);
    ref.invalidate(raceProvidersProvider);
  }
}

DnsProtocol _dnsProtocolOf(ProviderProtocol protocol) => switch (protocol) {
  ProviderProtocol.dns => DnsProtocol.dns,
  ProviderProtocol.doh => DnsProtocol.doh,
  ProviderProtocol.dot => DnsProtocol.dot,
};

final dnsProviderCatalogProvider =
    NotifierProvider<ProviderCatalogNotifier, List<MockProvider>>(
      ProviderCatalogNotifier.new,
    );

/// Providers the home picker may show: a protocol or per-provider switch hides entries, but never
/// the selected one.
final visibleProvidersProvider = Provider<List<MockProvider>>((ref) {
  final settings = ref.watch(legacySettingsProvider);
  final catalog = ref.watch(dnsProviderCatalogProvider);
  final selectedId = ref.watch(selectedProviderProvider);
  final visibleProtocols = settings.homeVisibleProtocols;
  final hidden = settings.homeHiddenProviderIds;
  final explicit = settings.homeVisibleProviderIds;
  return [
    for (final provider in catalog)
      if (provider.id == selectedId ||
          (visibleProtocols.contains(provider.protocol.name.toUpperCase())
              ? !hidden.contains(provider.id)
              : explicit.contains(provider.id)))
        provider,
  ];
});

class SelectedProviderNotifier extends Notifier<String> {
  @override
  String build() {
    final catalog = ref.watch(dnsProviderCatalogProvider);
    final id = ref.watch(legacySettingsProvider).selectedProviderId;
    if (catalog.any((provider) => provider.id == id)) return id;
    return catalog.isEmpty ? id : catalog.first.id;
  }

  /// Ignores unknown ids so a stale UI cannot persist one the engine cannot resolve.
  void select(String id) {
    if (!ref.read(dnsProviderCatalogProvider).any((p) => p.id == id)) return;
    ref.read(legacySettingsProvider).setSelectedProviderId(id);
    state = id;
  }
}

final selectedProviderProvider =
    NotifierProvider<SelectedProviderNotifier, String>(
      SelectedProviderNotifier.new,
    );

/// Provider set for the multi-provider resolution modes; the id lists are ordered, so writes keep
/// the stored order.
class RaceProvidersNotifier extends Notifier<Set<String>> {
  static const minCount = 2;

  @override
  Set<String> build() {
    final settings = ref.watch(legacySettingsProvider);
    final mode = ref.watch(resolutionModeProvider);
    final catalogIds = {
      for (final provider in ref.watch(dnsProviderCatalogProvider)) provider.id,
    };
    final stored = mode.isSingle
        ? settings.parallelRaceProviderIds
        : settings.providerIdsOf(mode.storageValue);
    final storedOrDefault = stored.isEmpty && mode.isSingle
        ? const ['preset_alidns_dns', 'preset_dnspod_dns']
        : stored;
    return {
      for (final id in storedOrDefault)
        if (catalogIds.contains(id)) id,
    };
  }

  /// Returns false when the removal would drop below [minCount].
  bool toggle(String id) {
    if (!ref.read(dnsProviderCatalogProvider).any((p) => p.id == id)) {
      return false;
    }
    final next = {...state};
    final removing = next.remove(id);
    if (removing && next.length < minCount) {
      return false;
    }
    if (!removing) {
      next.add(id);
    }
    _persist(next);
    state = next;
    return true;
  }

  void reset() {
    final settings = ref.read(legacySettingsProvider);
    final mode = ref.read(resolutionModeProvider);
    final defaults = {
      for (final provider in ref.read(dnsProviderCatalogProvider).take(2))
        provider.id,
    };
    _persist(defaults);
    state = defaults;
    if (!mode.isSingle) {
      // `_persist` already wrote the active mode's key.
      return;
    }
    settings.setParallelRaceProviderIds(defaults.toList());
  }

  /// Persists an explicit order; primary-backup keeps the sequence, the modes are sets.
  void reorder(List<String> ids) {
    final valid = {
      for (final provider in ref.read(dnsProviderCatalogProvider)) provider.id,
    };
    final ordered = [
      for (final id in ids)
        if (valid.contains(id)) id,
    ];
    final mode = ref.read(resolutionModeProvider);
    if (mode.isSingle) {
      ref.read(legacySettingsProvider).setParallelRaceProviderIds(ordered);
    } else {
      ref
          .read(legacySettingsProvider)
          .setProviderIdsOf(mode.storageValue, ordered);
    }
    state = ordered.toSet();
  }

  void _persist(Set<String> ids) {
    final settings = ref.read(legacySettingsProvider);
    final mode = ref.read(resolutionModeProvider);
    if (mode.isSingle) {
      settings.setParallelRaceProviderIds(ids.toList());
      return;
    }
    final key = mode.storageValue;
    if (key == 'primary_backup') {
      // Preserve the primary-to-backup order; newly added ids go last.
      final current = settings.providerIdsOf(key);
      final ordered = [
        for (final id in current)
          if (ids.contains(id)) id,
        for (final id in ids)
          if (!current.contains(id)) id,
      ];
      settings.setProviderIdsOf(key, ordered);
      return;
    }
    settings.setProviderIdsOf(key, ids.toList());
  }
}

final raceProvidersProvider =
    NotifierProvider<RaceProvidersNotifier, Set<String>>(
      RaceProvidersNotifier.new,
    );

/// Presets whose protocol follows the built-in protocol switch (legacy
/// `SWITCHABLE_PRESET_PROVIDER_NAMES`); every other provider keeps its own protocol.
Set<String> _switchablePresetNames(AppL10n l10n) => {
  l10n.upstreamPresetAliyun,
  l10n.upstreamPresetTencent,
};

/// The same preset in [protocol], or [id] unchanged for custom and non-switchable providers.
String presetIdForProtocol(String id, DnsProtocol protocol) {
  final presets = defaultDnsProviders(currentL10n);
  final preset = presets.where((p) => p.id == id).firstOrNull;
  if (preset == null ||
      !_switchablePresetNames(currentL10n).contains(preset.name)) {
    return id;
  }
  return presets
          .where((p) => p.name == preset.name && p.protocol == protocol)
          .firstOrNull
          ?.id ??
      id;
}

/// Built-in service protocol (`preset_dns_service`, stored as `DNS` / `DOT` / `DOH`).
class PresetProtocolNotifier extends Notifier<ProviderProtocol> {
  @override
  ProviderProtocol build() => switch (ref
      .watch(legacySettingsProvider)
      .presetDnsServiceRaw
      .toUpperCase()) {
    'DOT' => ProviderProtocol.dot,
    'DOH' => ProviderProtocol.doh,
    _ => ProviderProtocol.dns,
  };

  /// Remaps the switchable presets in all four modes' selections, as legacy
  /// `setPresetDnsService` does, then stores the protocol. Returns false when nothing changed.
  bool select(ProviderProtocol protocol) {
    if (state == protocol) return false;
    final settings = ref.read(legacySettingsProvider);
    final target = _dnsProtocolOf(protocol);
    String remap(String id) => presetIdForProtocol(id, target);
    List<String> remapAll(List<String> ids) => ids.map(remap).toSet().toList();

    settings.setSelectedProviderId(remap(settings.selectedProviderId));
    settings.setSmartPredictionProviderIds(
      remapAll(settings.smartPredictionProviderIds),
    );
    settings.setParallelRaceProviderIds(
      remapAll(settings.parallelRaceProviderIds),
    );
    settings.setPrimaryBackupProviderIds(
      remapAll(settings.primaryBackupProviderIds),
    );
    settings.setPresetDnsServiceRaw(switch (protocol) {
      ProviderProtocol.dns => 'DNS',
      ProviderProtocol.dot => 'DOT',
      ProviderProtocol.doh => 'DOH',
    });
    state = protocol;
    ref.invalidate(selectedProviderProvider);
    ref.invalidate(raceProvidersProvider);
    return true;
  }
}

final presetProtocolProvider =
    NotifierProvider<PresetProtocolNotifier, ProviderProtocol>(
      PresetProtocolNotifier.new,
    );
