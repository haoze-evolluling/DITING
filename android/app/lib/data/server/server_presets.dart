import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';

String serverProtocolForUi(ProviderProtocol protocol) => switch (protocol) {
  ProviderProtocol.dns => 'PLAIN',
  ProviderProtocol.doh => 'DOH',
  ProviderProtocol.dot => 'DOT',
};

ProviderProtocol serverUiProtocol(String protocol) => switch (protocol) {
  'DOH' || 'DOH3' => ProviderProtocol.doh,
  'DOT' => ProviderProtocol.dot,
  _ => ProviderProtocol.dns,
};

String serverProtocolLabel(String protocol) => switch (protocol) {
  'DOH' || 'DOH3' => ProviderProtocol.doh.label,
  'DOT' => ProviderProtocol.dot.label,
  _ => ProviderProtocol.dns.label,
};

String serverProviderPresetId(DnsProviderEntry provider) {
  final protocol = switch (provider.protocol) {
    DnsProtocol.dns => 'PLAIN',
    DnsProtocol.doh => 'DOH',
    DnsProtocol.dot => 'DOT',
  };
  return '${provider.name} (${serverProtocolLabel(protocol)})';
}

ServerProviderConfig serverProviderFromPreset(DnsProviderEntry provider) {
  final protocol = switch (provider.protocol) {
    DnsProtocol.dns => 'PLAIN',
    DnsProtocol.doh => 'DOH',
    DnsProtocol.dot => 'DOT',
  };
  return ServerProviderConfig(
    id: serverProviderPresetId(provider),
    protocol: protocol,
    server: protocol == 'DOH' ? '' : provider.address,
    url: protocol == 'DOH' ? provider.address : '',
  );
}

ServerBootstrapConfig serverBootstrapFromPreset(BootstrapEntry preset) =>
    ServerBootstrapConfig(id: preset.id, name: preset.name, address: preset.ip);
