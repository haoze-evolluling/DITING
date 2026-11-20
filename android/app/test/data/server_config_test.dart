import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_presets.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('服务器默认配置对齐普通模式且不预置订阅', () {
    final config = ServerConfig.defaults();

    expect(config.filter.lists, isEmpty);
    expect(config.upstream.mode, 'primary_backup');
    expect(config.upstream.providers.map((provider) => provider.protocol), [
      'PLAIN',
      'PLAIN',
    ]);
    expect(config.upstream.providers.map((provider) => provider.server), [
      '223.5.5.5:53',
      '119.29.29.29:53',
    ]);
    expect(config.upstream.bootstrap.map((entry) => entry.id), [
      'preset_volcengine',
      'preset_dnspod',
      'preset_alidns',
    ]);
  });

  test('普通模式预设转换时明文 DNS 使用 PLAIN', () {
    final plain = serverProviderFromPreset(
      const DnsProviderEntry(
        id: 'preset_360_dns',
        name: '360',
        protocol: DnsProtocol.dns,
        host: '101.226.4.6',
        port: 53,
      ),
    );
    final doh = serverProviderFromPreset(
      const DnsProviderEntry(
        id: 'preset_cloudflare_doh',
        name: 'Cloudflare',
        protocol: DnsProtocol.doh,
        url: 'https://cloudflare-dns.com/dns-query',
      ),
    );

    expect(plain.id, '360 (DNS)');
    expect(plain.protocol, 'PLAIN');
    expect(plain.server, '101.226.4.6:53');
    expect(plain.url, isEmpty);
    expect(doh.id, 'Cloudflare (DoH)');
    expect(doh.protocol, 'DOH');
    expect(doh.server, isEmpty);
    expect(doh.url, 'https://cloudflare-dns.com/dns-query');
  });
}
