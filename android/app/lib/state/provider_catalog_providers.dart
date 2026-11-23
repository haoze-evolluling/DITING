library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/provider_store.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

List<MockProvider> defaultProviderCatalog() => [
  for (final provider in defaultDnsProviders(currentL10n))
    provider.toMock(latencyMs: -1, isPreset: true),
];

ProviderProtocol _protocolOf(DnsProtocol protocol) => switch (protocol) {
  DnsProtocol.dns => ProviderProtocol.dns,
  DnsProtocol.doh => ProviderProtocol.doh,
  DnsProtocol.dot => ProviderProtocol.dot,
};

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

String endpointOfProvider(String id, List<MockProvider> catalog) {
  final provider = catalog.firstWhere(
    (candidate) => candidate.id == id,
    orElse: () => catalog.first,
  );
  return '${provider.protocol.label} · ${provider.address}';
}


String providerLatencyLabel(MockProvider provider) => provider.latencyMs < 0
    ? currentL10n.providerNotTested
    : currentL10n.providerLatencyValue(provider.latencyMs);

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

  void _commit(void Function(LegacySettings settings) write) {
    write(ref.read(legacySettingsProvider));
    ref.read(legacySettingsRevisionProvider.notifier).bump();
    _refresh();
  }

  void addCustom({
    required String name,
    required ProviderProtocol protocol,
    required String address,
  }) {
    _commit(
      (settings) => addUserProvider(
        settings,
        name: name,
        protocol: _dnsProtocolOf(protocol),
        address: address,
      ),
    );
  }

  void updateCustom({
    required String id,
    required String name,
    required ProviderProtocol protocol,
    required String address,
  }) {
    _commit(
      (settings) => updateUserProvider(
        settings,
        id: id,
        name: name,
        protocol: _dnsProtocolOf(protocol),
        address: address,
      ),
    );
    ref.invalidate(selectedProviderProvider);
    ref.invalidate(raceProvidersProvider);
  }

  void deleteCustom(String id) {
    _commit((settings) => deleteUserProvider(settings, id));
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

List<MockProvider> orderedProviders(
  List<MockProvider> catalog,
  List<String> order,
) {
  final byId = {for (final provider in catalog) provider.id: provider};
  final arranged = [for (final id in order) ?byId[id]];
  final arrangedIds = {for (final provider in arranged) provider.id};
  return [
    ...arranged,
    for (final provider in catalog)
      if (!arrangedIds.contains(provider.id)) provider,
  ];
}

List<String> reorderProviderIds({
  required List<String> order,
  required List<String> groupIds,
  required int oldIndex,
  required int newIndex,
}) {
  final moved = [...groupIds];
  moved.insert(newIndex, moved.removeAt(oldIndex));
  final slots = [
    for (var index = 0; index < order.length; index++)
      if (groupIds.contains(order[index])) index,
  ];
  final next = [...order];
  for (var index = 0; index < slots.length && index < moved.length; index++) {
    next[slots[index]] = moved[index];
  }
  return next;
}

final visibleProvidersProvider = Provider<List<MockProvider>>((ref) {
  final settings = ref.watch(legacySettingsProvider);
  final catalog = orderedProviders(
    ref.watch(dnsProviderCatalogProvider),
    settings.providerDisplayOrderIds,
  );
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
    final defaults = {
      for (final provider in ref.read(dnsProviderCatalogProvider).take(2))
        provider.id,
    };
    _persist(defaults);
    state = defaults;
  }

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

Set<String> _switchablePresetNames(AppL10n l10n) => {
  l10n.upstreamPresetAliyun,
  l10n.upstreamPresetTencent,
};

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
