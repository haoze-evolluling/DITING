// Server mode: the standalone DNS server config, its state machine, and the custom
// upstream list it publishes.

import 'dart:convert';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/server/dns_server_bridge.dart';
import 'package:diting_android/data/server/dns_server_config.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/server_upstream_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_dns_server_controller.dart';

void main() {
  group('服务器模式配置与状态机', _serverMode);
  group('自定义上游增删改', _serverUpstreams);
}

void _serverMode() {
  group('服务器模式配置', () {
    test('默认值：1053 端口、阿里云 PLAIN、均衡缓存、无 bootstrap', () {
      final config = buildServerDnsConfig(serverSettings({}));
      final json = config.toJson();
      expect(json['mode'], 'single');
      expect(json['blockResponse'], 'NXDOMAIN');
      expect(json['bootstrap'], {'enabled': false, 'ips': <Object?>[]});
      expect((json['providers'] as List).single, {
        'id': 'preset_alidns_dns',
        'protocol': 'PLAIN',
        'server': '223.5.5.5:53',
        'url': '',
      });
      final cache = json['cache'] as Map;
      expect(cache['enabled'], true);
      expect(cache['mode'], 'limit_max_ttl');
      expect(cache['minTtlEnabled'], true);
      expect(cache['staleFallbackEnabled'], true);
      expect(cache['negativeTtlSeconds'], 30);
    });

    test('竞速模式按候选列表生成多上游文档', () {
      final settings = serverSettings({
        'dns_resolution_mode': 'parallel_race',
        'parallel_race_provider_ids': jsonEncode([
          'preset_alidns_dns',
          'preset_dnspod_dns',
        ]),
      });
      final config = buildServerDnsConfig(settings);
      expect(config.mode, 'parallel_race');
      expect(config.providerCount, 2);
      expect(config.providers.map((u) => u.id), [
        'preset_alidns_dns',
        'preset_dnspod_dns',
      ]);
      expect(config.toJson()['mode'], 'parallel_race');
      expect((config.toJson()['providers'] as List), hasLength(2));
    });

    test('竞速候选不足两家时回落到所选上游', () {
      final settings = serverSettings({
        'dns_resolution_mode': 'primary_backup',
        'primary_backup_provider_ids': jsonEncode(['preset_dnspod_dns']),
        'selected_upstream_id': 'preset_alidns_dns',
      });
      final config = buildServerDnsConfig(settings);
      expect(config.mode, 'primary_backup');
      expect(config.providerCount, 1);
      expect(config.upstream.id, 'preset_alidns_dns');
    });

    test('保守与高命中率预设逐字对齐', () {
      final conservative =
          buildServerDnsConfig(serverSettings({'cache_preset': 'conservative'}))
                  .toJson()['cache']
              as Map;
      expect(conservative['mode'], 'follow_dns_ttl');
      expect(conservative['minTtlEnabled'], false);
      expect(conservative['negativeTtlSeconds'], 15);

      final high =
          buildServerDnsConfig(
                serverSettings({'cache_preset': 'high_hit_rate'}),
              ).toJson()['cache']
              as Map;
      expect(high['maxTtlSeconds'], 21600);
      expect(high['minTtlSeconds'], 120);
      expect(high['staleFallbackSeconds'], 900);

      final unknown =
          buildServerDnsConfig(serverSettings({'cache_preset': 'nope'}))
                  .toJson()['cache']
              as Map;
      expect(unknown['maxTtlSeconds'], 3600);
    });

    test('自定义上游解析、DOH 无 server、端口与协议校验', () {
      final settings = serverSettings({
        'selected_upstream_id': 'custom_doh',
        'custom_upstreams': jsonEncode([
          {
            'id': 'custom_doh',
            'name': '自定义 DoH',
            'address': 'https://dns.example/dns-query',
            'port': 443,
            'protocol': 'DOH',
          },
          {
            'id': 'custom_bad',
            'name': '坏地址',
            'address': 'http://x',
            'port': 443,
            'protocol': 'DOH',
          },
          {
            'id': 'custom_udp',
            'name': '自定义 UDP',
            'address': '9.9.9.9',
            'port': 5353,
            'protocol': 'DNS',
          },
        ]),
      });
      final config = buildServerDnsConfig(settings);
      expect(config.upstream.id, 'custom_doh');
      expect((config.toJson()['providers'] as List).single, {
        'id': 'custom_doh',
        'protocol': 'DOH',
        'server': '',
        'url': 'https://dns.example/dns-query',
      });
      final upstreams = serverUpstreams(settings);
      expect(upstreams.map((u) => u.id), contains('custom_udp'));
      expect(upstreams.map((u) => u.id), isNot(contains('custom_bad')));
    });

    test('DoT 自定义上游 hostPort 不带自造括号', () {
      final settings = serverSettings({
        'selected_upstream_id': 'custom_dot',
        'custom_upstreams': jsonEncode([
          {
            'id': 'custom_dot',
            'name': '自定义 DoT',
            'address': 'dot.example',
            'port': 853,
            'protocol': 'DOT',
          },
        ]),
      });
      final provider =
          (buildServerDnsConfig(settings).toJson()['providers'] as List).single
              as Map;
      expect(provider['server'], 'dot.example:853');
      expect(provider['protocol'], 'DOT');
    });

    test('阻断响应与动态升级键映射', () {
      final settings = serverSettings({
        'block_response_mode': 'zero_address',
        'block_response_dynamic_enabled': true,
        'block_response_dynamic_threshold': 999,
        'block_response_dynamic_window_seconds': 1,
        'block_response_dynamic_nxdomain_duration_seconds': 10,
      });
      final json = buildServerDnsConfig(settings).toJson();
      expect(json['blockResponse'], 'CUSTOM_IP');
      expect(json['dynamicResponse'], {
        'enabled': true,
        'requestThreshold': 100,
        'windowSeconds': 10,
        'nxDomainDurationSeconds': 60,
      });
    });
  });

  group('服务器状态机', () {
    ProviderContainer container(
      FakeDnsServerController controller, {
      Map<String, Object?> prefs = const {},
    }) {
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore({
              'diting_settings': {'app_work_mode': 'dns'},
              'diting_dns_mode_prefs': prefs,
            }),
          ),
          dnsServerControllerProvider.overrideWithValue(controller),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('启动使用旧版配置并写回 service_active', () async {
      final fake = FakeDnsServerController();
      final c = container(fake, prefs: {'local_listen_port': 2053});
      expect(c.read(serverStatusProvider), ServerStatus.stopped);

      await c.read(serverStatusProvider.notifier).toggle();
      expect(c.read(serverStatusProvider), ServerStatus.running);
      expect(fake.startCalls, 1);
      final request = fake.lastRequest!;
      expect(request.port, 2053);
      expect(request.dnsConfig, contains('"mode":"single"'));
      expect(request.dnsConfig, contains('"id":"preset_alidns_dns"'));
      expect(request.dnsConfig, contains('"bootstrap":{"enabled":false'));
      expect(request.adBlockEnabled, false);
      expect(c.read(legacySettingsProvider).serverServiceActive, true);
    });

    test('非服务器模式拒绝启动', () async {
      final fake = FakeDnsServerController();
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          dnsServerControllerProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(c.dispose);
      await c.read(serverStatusProvider.notifier).toggle();
      expect(c.read(serverStatusProvider), ServerStatus.error);
      expect(fake.startCalls, 0);
    });

    test('残留 service_active 以原生状态纠正', () async {
      final fake = FakeDnsServerController();
      final c = container(fake, prefs: {'service_active': true});
      expect(c.read(serverStatusProvider), ServerStatus.starting);
      await c.read(serverStatusProvider.notifier).syncStatus();
      expect(c.read(serverStatusProvider), ServerStatus.stopped);
      expect(c.read(legacySettingsProvider).serverServiceActive, false);
    });

    test('停止清标志', () async {
      final fake = FakeDnsServerController(
        statusValue: const DnsServerStatus(
          running: true,
          persisted: true,
          port: 1053,
        ),
      );
      final c = container(fake, prefs: {'service_active': true});
      await c.read(serverStatusProvider.notifier).syncStatus();
      expect(c.read(serverStatusProvider), ServerStatus.running);

      await c.read(serverStatusProvider.notifier).toggle();
      expect(fake.stopCalls, 1);
      expect(c.read(serverStatusProvider), ServerStatus.stopped);
      expect(c.read(legacySettingsProvider).serverServiceActive, false);
    });
  });
}

LegacySettings serverSettings(Map<String, Object?> values) => LegacySettings(
  MemoryLegacyPrefsStore({
    'diting_settings': {'app_work_mode': 'dns'},
    'diting_dns_mode_prefs': values,
  }),
);

/// Add, edit and delete for server-mode custom upstreams: ids must not start with `preset_`,
/// non-DoH addresses drop IPv6 brackets, and deleting the selected entry falls back to a preset
void _serverUpstreams() {
  late ProviderContainer container;

  ProviderContainer makeContainer() {
    final store = MemoryLegacyPrefsStore();
    return ProviderContainer(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
    );
  }

  setUp(() => container = makeContainer());
  tearDown(() => container.dispose());

  ServerUpstreamActions actions() =>
      container.read(serverUpstreamActionsProvider);

  List<ServerUpstream> custom() => parseServerCustomUpstreams(
    container.read(legacySettingsProvider).serverCustomUpstreamsJson,
  );

  test('新增后落盘，id 带 custom_ 前缀', () {
    final saved = actions().add(
      name: '我的 DoH',
      protocol: DnsProtocol.doh,
      address: 'https://dns.example.com/dns-query',
      port: 443,
    );
    expect(saved, isNotNull);
    expect(saved!.id.startsWith('preset_'), isFalse);
    expect(saved.id.startsWith('custom_'), isTrue);

    final list = custom();
    expect(list, hasLength(1));
    expect(list.single.name, '我的 DoH');
    expect(list.single.protocol, DnsProtocol.doh);
    expect(list.single.address, 'https://dns.example.com/dns-query');
  });

  test('非 DoH 地址落盘时去掉 IPv6 方括号', () {
    final saved = actions().add(
      name: 'IPv6 DNS',
      protocol: DnsProtocol.dns,
      address: '[2001:db8::1]',
      port: 53,
    );
    expect(saved!.address, '2001:db8::1');
    expect(custom().single.address, '2001:db8::1');
  });

  test('校验不过时不落盘', () {
    expect(
      actions().add(
        name: '  ',
        protocol: DnsProtocol.dns,
        address: '1.1.1.1',
        port: 53,
      ),
      isNull,
    );
    expect(
      actions().add(
        name: '明文 DoH',
        protocol: DnsProtocol.doh,
        address: 'http://doh.example/dns-query',
        port: 443,
      ),
      isNull,
    );
    expect(
      actions().add(
        name: '端口越界',
        protocol: DnsProtocol.dns,
        address: '1.1.1.1',
        port: 70000,
      ),
      isNull,
    );
    expect(custom(), isEmpty);
  });

  test('编辑自定义项会更新内容且保持 id', () {
    final saved = actions().add(
      name: '原名',
      protocol: DnsProtocol.dns,
      address: '1.1.1.1',
      port: 53,
    )!;
    final ok = actions().update(
      ServerUpstream(
        id: saved.id,
        name: '新名',
        protocol: DnsProtocol.dot,
        address: 'dns.example.com',
        port: 853,
      ),
    );
    expect(ok, isTrue);
    final list = custom();
    expect(list, hasLength(1));
    expect(list.single.id, saved.id);
    expect(list.single.name, '新名');
    expect(list.single.protocol, DnsProtocol.dot);
    expect(list.single.port, 853);
  });

  test('内置项不可编辑也不可删除', () {
    final preset = serverPresetUpstreams(lookupAppL10n(const Locale('zh'))).first;
    expect(actions().update(preset), isFalse);
    expect(actions().remove(preset.id), isFalse);
    expect(custom(), isEmpty);
  });

  test('删除当前选中的自定义项 → 回落到第一个内置', () {
    final saved = actions().add(
      name: '待删',
      protocol: DnsProtocol.dns,
      address: '1.2.3.4',
      port: 53,
    )!;
    container.read(serverSelectedUpstreamProvider.notifier).select(saved.id);
    expect(
      container.read(legacySettingsProvider).serverSelectedUpstreamId,
      saved.id,
    );

    expect(actions().remove(saved.id), isTrue);
    expect(
      container.read(legacySettingsProvider).serverSelectedUpstreamId,
      serverPresetUpstreams(lookupAppL10n(const Locale('zh'))).first.id,
    );
    expect(custom(), isEmpty);
  });

  test('选中的自定义上游会被 buildServerDnsConfig 用上', () {
    final saved = actions().add(
      name: '我的上游',
      protocol: DnsProtocol.dns,
      address: '9.9.9.9',
      port: 53,
    )!;
    container.read(serverSelectedUpstreamProvider.notifier).select(saved.id);

    final config = buildServerDnsConfig(container.read(legacySettingsProvider));
    expect(config.upstream.name, '我的上游');
    expect(config.upstream.address, '9.9.9.9');
  });

  test('encode 只写五个字段（与旧版序列化一致）', () {
    final json = encodeServerCustomUpstreams([
      const ServerUpstream(
        id: 'custom_x',
        name: 'X',
        protocol: DnsProtocol.dot,
        address: 'dot.example',
        port: 853,
      ),
    ]);
    expect(json, contains('"id"'));
    expect(json, contains('"name"'));
    expect(json, contains('"protocol"'));
    expect(json, contains('"address"'));
    expect(json, contains('"port"'));
    expect(json.contains('isCustom'), isFalse);
    expect(json, contains('DOT'));
  });

  group('validateServerUpstream', () {
    test('名称为空 → 拒绝', () {
      expect(
        validateServerUpstream(
          name: '',
          protocol: DnsProtocol.dns,
          address: '1.1.1.1',
          port: 53,
        ),
        isA<UpstreamInvalid>(),
      );
    });

    test('DoH 非 https → 拒绝', () {
      final result = validateServerUpstream(
        name: 'x',
        protocol: DnsProtocol.doh,
        address: 'dns.example.com',
        port: 443,
      );
      expect(result, isA<UpstreamInvalid>());
      expect((result as UpstreamInvalid).message, contains('https://'));
    });

    test('合法 DoT（853）→ 通过', () {
      expect(
        validateServerUpstream(
          name: 'x',
          protocol: DnsProtocol.dot,
          address: 'dot.example.com',
          port: 853,
        ),
        isA<UpstreamOk>(),
      );
    });

    test('端口 0 → 拒绝', () {
      expect(
        validateServerUpstream(
          name: 'x',
          protocol: DnsProtocol.dns,
          address: '1.1.1.1',
          port: 0,
        ),
        isA<UpstreamInvalid>(),
      );
    });
  });
}
