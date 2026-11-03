/// Legacy provider catalog: presets live in code, only custom providers persist
/// (`user_providers_json`), which is what the engine reads.
library;

import 'dart:convert';

import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';

class UserProviderRecord {
  const UserProviderRecord({
    required this.id,
    required this.name,
    required this.protocol,
    this.url = '',
    this.host = '',
    this.port = 853,
  });

  final String id;
  final String name;
  final DnsProtocol protocol;
  final String url;
  final String host;
  final int port;

  String get address => protocol == DnsProtocol.doh ? url : '$host:$port';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.storageValue,
    'url': url,
    'host': host,
    'port': port,
  };
}

/// Parses `user_providers_json`, dropping the same rows 1.4.3 drops: unknown protocol, blank
/// id/name, DoH without https, bad host/port.
List<UserProviderRecord> readUserProviders(LegacySettings settings) {
  final raw = settings.userProvidersJson;
  if (raw == null || raw.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final result = <UserProviderRecord>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final protocol = DnsProtocol.fromStorage(item['protocol'] as String?);
    final id = item['id'] as String?;
    final name = item['name'] as String?;
    if (protocol == null || id == null || id.isEmpty || name == null) {
      continue;
    }
    if (name.isEmpty) continue;
    final url = (item['url'] as String?)?.trim() ?? '';
    final host = (item['host'] as String?)?.trim() ?? '';
    final port = item['port'] is int
        ? item['port'] as int
        : _defaultPort(protocol);
    if (protocol == DnsProtocol.doh) {
      if (!url.toLowerCase().startsWith('https://')) continue;
      result.add(
        UserProviderRecord(id: id, name: name, protocol: protocol, url: url),
      );
    } else {
      if (host.isEmpty || port < 1 || port > 65535) continue;
      result.add(
        UserProviderRecord(
          id: id,
          name: name,
          protocol: protocol,
          host: host,
          port: port,
        ),
      );
    }
  }
  return result;
}

void writeUserProviders(
  LegacySettings settings,
  List<UserProviderRecord> providers,
) {
  settings.setUserProvidersJson(
    jsonEncode([for (final provider in providers) provider.toJson()]),
  );
}

UserProviderRecord addUserProvider(
  LegacySettings settings, {
  required String name,
  required DnsProtocol protocol,
  required String address,
  String? id,
}) {
  final (url, host, port) = _splitAddress(protocol, address);
  final record = UserProviderRecord(
    id: id ?? 'user_${DateTime.now().microsecondsSinceEpoch}',
    name: name.trim(),
    protocol: protocol,
    url: url,
    host: host,
    port: port,
  );
  writeUserProviders(settings, [...readUserProviders(settings), record]);
  return record;
}

void updateUserProvider(
  LegacySettings settings, {
  required String id,
  required String name,
  required DnsProtocol protocol,
  required String address,
}) {
  final (url, host, port) = _splitAddress(protocol, address);
  final updated = [
    for (final provider in readUserProviders(settings))
      if (provider.id == id)
        UserProviderRecord(
          id: id,
          name: name.trim(),
          protocol: protocol,
          url: url,
          host: host,
          port: port,
        )
      else
        provider,
  ];
  writeUserProviders(settings, updated);
}

/// Removes a custom provider and scrubs it from every reference.
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

/// `1.1.1.1:853` to host/port; DoH keeps the URL and clears host/port.
(String url, String host, int port) _splitAddress(
  DnsProtocol protocol,
  String address,
) {
  final trimmed = address.trim();
  if (protocol == DnsProtocol.doh) {
    return (trimmed, '', 853);
  }
  final separator = trimmed.lastIndexOf(':');
  if (separator <= 0) {
    return ('', trimmed, _defaultPort(protocol));
  }
  final host = trimmed.substring(0, separator);
  final port =
      int.tryParse(trimmed.substring(separator + 1)) ?? _defaultPort(protocol);
  return ('', host, port);
}

/// Plain DNS falls back to 53, DoT to 853.
int _defaultPort(DnsProtocol protocol) =>
    protocol == DnsProtocol.dot ? 853 : 53;
