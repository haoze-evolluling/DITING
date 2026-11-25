part of 'tunnel_state_test.dart';

void _rootTakeover() {
  ProviderContainer container({
    required FakeVpnController normal,
    required FakeVpnController root,
    String workMode = 'express',
    Map<String, Object?> prefs = const {},
  }) {
    final store = MemoryLegacyPrefsStore({
      'diting_settings': {'app_work_mode': workMode},
      'dns_vpn_prefs': {'root_dns_takeover_enabled': true, ...prefs},
    });
    final c = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(store),
        vpnControllerProvider.overrideWithValue(normal),
        rootDnsControllerProvider.overrideWithValue(root),
        ruleRepositoryProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('Root 免 VPN 接管', () {
    test('开启时启动走 Root 通道并写 root_dns_running', () async {
      final normal = FakeVpnController();
      final root = FakeVpnController();
      final c = container(normal: normal, root: root);
      expect(c.read(powerProvider), PowerState.stopped);

      await c.read(powerProvider.notifier).toggle();

      expect(c.read(powerProvider), PowerState.starting);
      expect(root.startCalls, 1);
      expect(normal.startCalls, 0);
      expect(c.read(legacySettingsProvider).rootDnsRunning, isTrue);

      root.statusValue = const VpnStatus(running: true, persisted: true);
      await c.read(powerProvider.notifier).syncStatus();
      expect(c.read(powerProvider), PowerState.running);
      final json = jsonDecode(root.lastRequest!.dnsConfig) as Map;
      expect(json['mode'], isNotNull);
    });

    test('残留的 root_dns_running 用 Root 状态恢复', () async {
      final normal = FakeVpnController();
      final root = FakeVpnController()
        ..statusValue = const VpnStatus(
          running: true,
          persisted: true,
          stats: {'queries': 4},
        );
      final c = container(
        normal: normal,
        root: root,
        prefs: {'root_dns_running': true},
      );

      expect(c.read(powerProvider), PowerState.starting);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(powerProvider), PowerState.running);
      expect(root.startCalls, 0);
      expect(normal.startCalls, 0);
    });

    test('普通模式忽略 Root 接管开关，固定走全隧道', () async {
      final normal = FakeVpnController();
      final root = FakeVpnController();
      final c = container(
        normal: normal,
        root: root,
        workMode: 'normal',
      );

      await c.read(powerProvider.notifier).toggle();

      expect(root.startCalls, 0);
      expect(normal.startCalls, 1);
      expect(c.read(powerProvider), PowerState.running);
      expect(c.read(legacySettingsProvider).vpnRunning, isTrue);
      expect(c.read(legacySettingsProvider).rootDnsRunning, isFalse);
    });

    test('关闭接管开关时先停止正在运行的 Root 服务', () async {
      final normal = FakeVpnController();
      final root = FakeVpnController();
      final c = container(normal: normal, root: root);
      await c.read(powerProvider.notifier).toggle();
      root.statusValue = const VpnStatus(running: true, persisted: true);
      await c.read(powerProvider.notifier).syncStatus();
      expect(c.read(powerProvider), PowerState.running);

      await c.read(rootDnsTakeoverProvider.notifier).set(false);

      expect(root.stopCalls, 1);
      expect(normal.stopCalls, 0);
      expect(c.read(legacySettingsProvider).rootDnsTakeoverEnabled, isFalse);
      expect(c.read(legacySettingsProvider).rootDnsRunning, isFalse);
      expect(c.read(powerProvider), PowerState.stopped);
    });
  });
}
