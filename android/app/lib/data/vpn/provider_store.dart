library;

import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/rust_dns_config_core.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

List<DnsProviderEntry> readUserProviders(LegacySettings settings) =>
    parseUserProviders(settings.userProvidersJson);

void writeUserProviders(
  LegacySettings settings,
  List<DnsProviderEntry> providers,
) {
  settings.setUserProvidersJson(
    RustDnsConfigCore.instance.encodeUserProviders([
      for (final provider in providers) providerRowOf(provider),
    ]),
  );
}

DnsProviderEntry addUserProvider(
  LegacySettings settings, {
  required String name,
  required DnsProtocol protocol,
  required String address,
  String? id,
}) {
  final providers = readUserProviders(settings);
  final next = _upsert(
    providers,
    id: id ?? 'user_${DateTime.now().microsecondsSinceEpoch}',
    name: name,
    protocol: protocol,
    address: address,
  );
  writeUserProviders(settings, next);
  return next.last;
}

void updateUserProvider(
  LegacySettings settings, {
  required String id,
  required String name,
  required DnsProtocol protocol,
  required String address,
}) {
  final next = _upsert(
    readUserProviders(settings),
    id: id,
    name: name,
    protocol: protocol,
    address: address,
  );
  writeUserProviders(settings, next);
}

void deleteUserProvider(LegacySettings settings, String id) {
  writeUserProviders(settings, [
    for (final provider in readUserProviders(settings))
      if (provider.id != id) provider,
  ]);
  if (settings.selectedProviderId == id) {
    settings.setSelectedProviderId('preset_alidns_dns');
  }
  for (final mode in const [
    'smart_prediction',
    'parallel_race',
    'primary_backup',
  ]) {
    final ids = settings.providerIdsOf(mode);
    if (ids.contains(id)) {
      settings.setProviderIdsOf(mode, [
        for (final item in ids)
          if (item != id) item,
      ]);
    }
  }
}

List<DnsProviderEntry> _upsert(
  List<DnsProviderEntry> providers, {
  required String id,
  required String name,
  required DnsProtocol protocol,
  required String address,
}) => [
  for (final row in RustDnsConfigCore.instance.upsertUserProvider(
    [for (final provider in providers) providerRowOf(provider)],
    id: id,
    name: name,
    protocolStorage: protocol.storageValue,
    address: address,
  ))
    providerEntryOf(row),
];
