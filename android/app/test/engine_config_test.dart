// The DNS config handed to the Go engine: provider catalog, cache presets, block
// response and the race list all come from 1.4.3 keys.

import 'dart:convert';

import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/block_response_settings.dart';
import 'package:diting_android/data/vpn/cache_presets.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/provider_store.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('服务商与缓存配置', _providerCatalog);
  group('VPN DNS 配置', _vpnConfig);
}

/// Locks that the UI writes the fixed prefs keys the engine reads (providers, cache, app rules)
void _providerCatalog() {
  ProviderContainer container({Map<String, Object?> dns = const {}}) {
    final store = MemoryLegacyPrefsStore({
      'dns_vpn_prefs': dns,
      'diting_express_prefs': const {},
      'diting_settings': const {'app_work_mode': 'normal'},
    });
    final c = ProviderContainer(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('自定义服务商落盘', () {
    test('新增 DoH 写 user_providers_json 并回读', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      addUserProvider(
        settings,
        name: ' 自建 DoH ',
        protocol: DnsProtocol.doh,
        address: 'https://dns.example.com/query',
        id: 'user_1',
      );

      final records = readUserProviders(settings);
      expect(records, hasLength(1));
      expect(records.single.name, '自建 DoH');
      expect(records.single.url, 'https://dns.example.com/query');
      expect(records.single.address, 'https://dns.example.com/query');

      final json = jsonDecode(settings.userProvidersJson!) as List;
      expect((json.single as Map)['protocol'], 'DOH');
    });

    test('DoT 地址按 host:port 拆分，缺省端口 853', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      addUserProvider(
        settings,
        name: '自建 DoT',
        protocol: DnsProtocol.dot,
        address: 'dot.example.com:8853',
        id: 'user_2',
      );
      final record = readUserProviders(settings).single;
      expect(record.host, 'dot.example.com');
      expect(record.port, 8853);
      expect(record.address, 'dot.example.com:8853');
    });

    test('非法条目在读取时被丢弃，与旧版校验一致', () {
      final settings = LegacySettings(
        MemoryLegacyPrefsStore({
          'dns_vpn_prefs': {
            'user_providers_json': jsonEncode([
              {
                'id': 'a',
                'name': '无 https',
                'protocol': 'DOH',
                'url': 'http://x',
              },
              {
                'id': 'b',
                'name': '端口越界',
                'protocol': 'DOT',
                'host': 'x',
                'port': 70000,
              },
              {'id': 'c', 'name': '未知协议', 'protocol': 'QUIC', 'host': 'x'},
              {
                'id': 'd',
                'name': '可用',
                'protocol': 'DOT',
                'host': 'd.example',
                'port': 853,
              },
            ]),
          },
        }),
      );
      expect(readUserProviders(settings).map((item) => item.id), ['d']);
    });

    test('普通 DNS 缺省端口是 53，IPv6 地址带方括号', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      addUserProvider(
        settings,
        name: '自建 DNS',
        protocol: DnsProtocol.dns,
        address: 'dns.example.com',
        id: 'user_3',
      );
      addUserProvider(
        settings,
        name: '自建 IPv6',
        protocol: DnsProtocol.dot,
        address: joinHostPort('::1', 853),
        id: 'user_4',
      );
      final records = readUserProviders(settings);
      expect(records.first.port, 53);
      expect(records.first.address, 'dns.example.com:53');
      expect(records.last.address, '[::1]:853');
    });

    test('编辑保留 id，删除会清掉选中项与三种模式引用', () {
      final seed = jsonEncode([
        {
          'id': 'user_1',
          'name': '旧名',
          'protocol': 'DOT',
          'host': 'old',
          'port': 853,
        },
      ]);
      final settings = LegacySettings(
        MemoryLegacyPrefsStore({
          'dns_vpn_prefs': {
            'user_providers_json': seed,
            'selected_provider_id': 'user_1',
            'smart_prediction_provider_ids': '["user_1"]',
            'parallel_race_provider_ids': '["user_1","preset_alidns_dns"]',
            'primary_backup_provider_ids': '["preset_alidns_dns","user_1"]',
          },
        }),
      );

      updateUserProvider(
        settings,
        id: 'user_1',
        name: '新名',
        protocol: DnsProtocol.dot,
        address: 'new.example:853',
      );
      expect(readUserProviders(settings).single.name, '新名');
      expect(readUserProviders(settings).single.host, 'new.example');

      deleteUserProvider(settings, 'user_1');
      expect(readUserProviders(settings), isEmpty);
      expect(settings.selectedProviderId, 'preset_alidns_dns');
      expect(settings.smartPredictionProviderIds, isEmpty);
      expect(settings.parallelRaceProviderIds, ['preset_alidns_dns']);
      expect(settings.primaryBackupProviderIds, ['preset_alidns_dns']);
    });
  });

  group('缓存预设', () {
    test('三档预设各自写满 9 个 v2 键，并可从引擎侧读回', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      DnsCachePreset.highHitRate.applyTo(settings, enabled: true);

      expect(settings.cachePresetRaw, 'high_hit_rate');
      expect(settings.cacheEnabled, isTrue);
      expect(settings.cacheModeRaw, 'limit_max_ttl');
      expect(settings.cacheMaxTtlSeconds, 21600);
      expect(settings.cacheMinTtlEnabled, isTrue);
      expect(settings.cacheMinTtlSeconds, 120);
      expect(settings.cacheStaleFallbackEnabled, isTrue);
      expect(settings.cacheStaleFallbackSeconds, 900);

      final config = buildDnsConfig(settings);
      final cache = config.toJson(settings)['cache'] as Map;
      expect(cache['maxTtlSeconds'], 21600);
      expect(cache['minTtlSeconds'], 120);
    });

    test('缺少 preset 键时按策略推断，旧安装不会显示空档位', () {
      final conservative = LegacySettings(
        MemoryLegacyPrefsStore({
          'dns_vpn_prefs': {
            'dns_cache_mode_v2': 'follow_dns_ttl',
            'dns_cache_min_ttl_enabled_v2': false,
            'dns_cache_stale_fallback_enabled_v2': false,
          },
        }),
      );
      expect(DnsCachePreset.current(conservative), DnsCachePreset.conservative);

      final legacyBalanced = LegacySettings(
        MemoryLegacyPrefsStore({
          'dns_vpn_prefs': {
            'dns_cache_mode_v2': 'limit_max_ttl',
            'dns_cache_max_ttl_seconds_v2': 1800,
            'dns_cache_min_ttl_enabled_v2': true,
            'dns_cache_min_ttl_seconds_v2': 30,
            'dns_cache_stale_fallback_enabled_v2': false,
          },
        }),
      );
      expect(DnsCachePreset.current(legacyBalanced), DnsCachePreset.balanced);
    });
  });

  group('拦截响应', () {
    test('默认关闭动态策略，固定模式为 NXDOMAIN', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      expect(settings.blockResponseModeRaw, 'nxdomain');
      expect(DynamicBlockPolicy.read(settings).enabled, isFalse);
      expect(DynamicBlockPolicy.read(settings).requestThreshold, 5);
      expect(DynamicBlockPolicy.read(settings).windowSeconds, 60);
      expect(DynamicBlockPolicy.read(settings).nxDomainDurationSeconds, 300);
    });

    test('越界参数在落盘时被夹到旧版区间', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      DynamicBlockPolicy.defaults
          .copyWith(
            enabled: true,
            requestThreshold: 500,
            windowSeconds: 1,
            nxDomainDurationSeconds: 99999,
          )
          .write(settings);

      expect(settings.dynamicBlockEnabled, isTrue);
      expect(settings.dynamicBlockRequestThreshold, 100);
      expect(settings.dynamicBlockWindowSeconds, 10);
      expect(settings.dynamicBlockNxDomainDurationSeconds, 3600);

      final json =
          buildDnsConfig(settings).toJson(settings)['dynamicResponse'] as Map;
      expect(json['requestThreshold'], 100);
      expect(json['windowSeconds'], 10);
      expect(json['nxDomainDurationSeconds'], 3600);
    });
  });

  group('服务显示过滤', () {
    test('协议关闭后只保留显式开启与当前选中项', () {
      final c = container(
        dns: {
          'home_visible_protocols': '["DOH"]',
          'home_hidden_provider_ids': '[]',
          'home_visible_provider_ids': '["preset_alidns_dot"]',
          'selected_provider_id': 'preset_google_dns',
        },
      );
      final visible = c.read(visibleProvidersProvider);
      final ids = visible.map((provider) => provider.id).toSet();
      expect(ids, contains('preset_alidns_dot'));
      // The current selection is always kept, so the user can see it.
      expect(ids, contains('preset_google_dns'));
      expect(ids, isNot(contains('preset_cloudflare_dns')));
    });
  });

  group('竞速列表与单选', () {
    test('单选选择写入 selected_provider_id', () {
      final c = container();
      c.read(selectedProviderProvider.notifier).select('preset_cloudflare_doh');
      expect(
        c.read(legacySettingsProvider).selectedProviderId,
        'preset_cloudflare_doh',
      );
      expect(c.read(selectedProviderProvider), 'preset_cloudflare_doh');
    });

    test('未知 id 不会被写入，避免引擎解析不到', () {
      final c = container();
      final before = c.read(selectedProviderProvider);
      c.read(selectedProviderProvider.notifier).select('nope');
      expect(c.read(selectedProviderProvider), before);
      expect(c.read(legacySettingsProvider).selectedProviderId, isNot('nope'));
    });

    test('单选模式下竞速列表最少保留两项', () {
      final c = container();
      final notifier = c.read(raceProvidersProvider.notifier);
      expect(c.read(raceProvidersProvider), hasLength(2));
      expect(notifier.toggle('preset_alidns_dns'), isFalse);
      expect(c.read(raceProvidersProvider), hasLength(2));
    });

    test('切换解析模式读取各自的列表键', () {
      final c = container(
        dns: {
          'smart_prediction_provider_ids': '["preset_google_doh"]',
          'parallel_race_provider_ids':
              '["preset_alidns_dns","preset_dnspod_dns"]',
        },
      );
      c.read(resolutionModeProvider.notifier).select(ResolutionMode.smart);
      expect(c.read(raceProvidersProvider), {'preset_google_doh'});
    });
  });
}

void _vpnConfig() {
  group('DNS 配置', () {
    test('默认单一模式选中阿里云 PLAIN，服务端带端口', () {
      final settings = settingsWith({});
      final config = buildDnsConfig(settings);
      final json = config.toJson(settings);

      expect(json['mode'], 'single');
      expect(json['blockResponse'], 'NXDOMAIN');
      final providers = json['providers'] as List;
      expect(providers, hasLength(1));
      expect(providers.single, {
        'id': 'preset_alidns_dns',
        'protocol': 'PLAIN',
        'server': '223.5.5.5:53',
        'url': '',
      });
    });

    test('DoH 服务商 server 为空，url 原样保留', () {
      final settings = settingsWith({
        'selected_provider_id': 'preset_cloudflare_doh',
      });
      final provider =
          (buildDnsConfig(settings).toJson(settings)['providers'] as List)
                  .single
              as Map;
      expect(provider['protocol'], 'DOH');
      expect(provider['server'], '');
      expect(provider['url'], 'https://cloudflare-dns.com/dns-query');
    });

    test('竞速模式使用竞速列表；不足两个时回落到选中项', () {
      final two = settingsWith({'dns_resolution_mode': 'parallel_race'});
      expect(buildDnsConfig(two).providers.map((p) => p.id), [
        'preset_alidns_dns',
        'preset_dnspod_dns',
      ]);

      final one = settingsWith({
        'dns_resolution_mode': 'parallel_race',
        'parallel_race_provider_ids': jsonEncode(['preset_google_dns']),
      });
      expect(buildDnsConfig(one).providers.single.id, 'preset_alidns_dns');
      expect(buildDnsConfig(one).mode, 'parallel_race');
    });

    test('阻断响应与缓存默认值逐字对齐 1.4.3', () {
      final settings = settingsWith({'block_response_mode': 'zero_address'});
      final json = buildDnsConfig(settings).toJson(settings);
      expect(json['blockResponse'], 'CUSTOM_IP');
      expect(json['cache'], {
        'enabled': true,
        'mode': 'limit_max_ttl',
        'maxTtlSeconds': 3600,
        'fixedTtlSeconds': 3600,
        'minTtlEnabled': false,
        'minTtlSeconds': 60,
        'staleFallbackEnabled': false,
        'staleFallbackSeconds': 300,
        'negativeTtlEnabled': true,
        'negativeTtlSeconds': 30,
      });
    });

    test('bootstrap 只带选中的预置项', () {
      final settings = settingsWith({});
      final bootstrap =
          buildDnsConfig(settings).toJson(settings)['bootstrap'] as Map;
      expect(bootstrap['enabled'], true);
      expect((bootstrap['ips'] as List).map((e) => (e as Map)['ip']), [
        '223.5.5.5',
        '119.29.29.29',
        '180.184.1.1',
      ]);
    });
  });
}

LegacySettings settingsWith(Map<String, Object?> values) =>
    LegacySettings(MemoryLegacyPrefsStore({'dns_vpn_prefs': values}));
