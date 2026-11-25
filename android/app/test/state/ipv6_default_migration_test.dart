import 'package:diting_shared/data/prefs/ipv6_default_migration.dart';
import 'package:diting_shared/data/prefs/ipv6_mode.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IPv6 默认仅 IPv4 迁移', () {
    test('升级前显式选择自动的用户迁移为仅 IPv4', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'vpn_ipv6_mode': 'auto'},
      });

      migrateIpv6DefaultToIpv4(store);

      expect(LegacySettings(store).ipv6Mode, Ipv6Mode.ipv4);
      expect(store.read('dns_vpn_prefs', 'vpn_ipv6_enabled'), isFalse);
      expect(store.read('dns_vpn_prefs', 'dns_aaaa_enabled'), isFalse);
    });

    test('升级前选择 IPv6 优先的用户保持不变', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'vpn_ipv6_mode': 'ipv6'},
      });

      migrateIpv6DefaultToIpv4(store);

      expect(LegacySettings(store).ipv6Mode, Ipv6Mode.ipv6);
      expect(store.read('dns_vpn_prefs', 'vpn_ipv6_enabled'), isNull);
    });

    test('只有旧布尔开关的自动用户也迁移为仅 IPv4', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'vpn_ipv6_enabled': true, 'dns_aaaa_enabled': true},
      });

      migrateIpv6DefaultToIpv4(store);

      expect(LegacySettings(store).ipv6Mode, Ipv6Mode.ipv4);
      expect(store.read('dns_vpn_prefs', 'vpn_ipv6_enabled'), isFalse);
      expect(store.read('dns_vpn_prefs', 'dns_aaaa_enabled'), isFalse);
    });

    test('普通模式与简洁模式各自迁移，互不影响', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'vpn_ipv6_mode': 'auto'},
        'diting_express_prefs': {'vpn_ipv6_mode': 'auto'},
      });

      migrateIpv6DefaultToIpv4(store);

      final normal = LegacySettings(store);
      expect(normal.ipv6Mode, Ipv6Mode.ipv4);
      expect(normal.forExpress().ipv6Mode, Ipv6Mode.ipv4);
    });

    test('同步迁移上次启动参数，磁贴冷启动不会回到自动', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'last_ipv6_mode': 'auto',
          'last_tunnel_ipv6': true,
          'last_dns_aaaa': true,
        },
        'express_vpn_prefs': {
          'last_ipv6_mode': 'auto',
          'last_tunnel_ipv6': true,
          'last_dns_aaaa': true,
        },
      });

      migrateIpv6DefaultToIpv4(store);

      for (final container in const ['dns_vpn_prefs', 'express_vpn_prefs']) {
        expect(store.read(container, 'last_ipv6_mode'), 'ipv4');
        expect(store.read(container, 'last_tunnel_ipv6'), isFalse);
        expect(store.read(container, 'last_dns_aaaa'), isFalse);
      }
    });

    test('IPv6 优先的用户连同上一次启动参数都保持不变', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'vpn_ipv6_mode': 'ipv6',
          'last_ipv6_mode': 'ipv6',
          'last_tunnel_ipv6': true,
          'last_dns_aaaa': true,
        },
      });

      migrateIpv6DefaultToIpv4(store);

      expect(store.read('dns_vpn_prefs', 'last_ipv6_mode'), 'ipv6');
      expect(store.read('dns_vpn_prefs', 'last_tunnel_ipv6'), isTrue);
      expect(store.read('dns_vpn_prefs', 'last_dns_aaaa'), isTrue);
    });

    test('迁移只执行一次，之后用户仍可主动选择自动', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'vpn_ipv6_mode': 'auto'},
      });
      migrateIpv6DefaultToIpv4(store);
      final settings = LegacySettings(store);

      settings.setIpv6Mode(Ipv6Mode.auto);
      migrateIpv6DefaultToIpv4(store);

      expect(settings.ipv6Mode, Ipv6Mode.auto);
    });

    test('空存储首次启动落默认值与迁移标记', () {
      final store = MemoryLegacyPrefsStore();

      migrateIpv6DefaultToIpv4(store);

      expect(LegacySettings(store).ipv6Mode, Ipv6Mode.ipv4);
      expect(
        store.read('dns_vpn_prefs', LegacySettings.ipv6DefaultIpv4MigratedKey),
        isTrue,
      );
      expect(
        store.read(
          'diting_express_prefs',
          LegacySettings.ipv6DefaultIpv4MigratedKey,
        ),
        isTrue,
      );
    });
  });
}
