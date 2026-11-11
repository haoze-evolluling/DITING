part of 'tunnel_state_test.dart';

void _engineStats() {
  group('原生状态里的引擎计数', () {
    test('VpnStatus 解析 stats，缺失时为常量空表', () {
      final withStats = VpnStatus.fromMap({
        'running': true,
        'persisted': true,
        'stats': {'queries': 12, 'blocked': 3, 'cacheHits': 7},
      });
      expect(withStats.stats['queries'], 12);
      expect(withStats.stats['blocked'], 3);

      final empty = VpnStatus.fromMap({'running': false});
      expect(empty.stats, isEmpty);
    });

    test('解析原生启动时间戳，缺失或为零时为 null', () {
      final started = DateTime(2026, 10, 1, 8, 30);
      final vpn = VpnStatus.fromMap({
        'running': true,
        'startedAt': started.millisecondsSinceEpoch,
      });
      expect(vpn.startedAt, started);

      final server = DnsServerStatus.fromMap({
        'running': true,
        'startedAt': started.millisecondsSinceEpoch,
      });
      expect(server.startedAt, started);

      expect(VpnStatus.fromMap({'running': true}).startedAt, isNull);
      expect(
        VpnStatus.fromMap({'running': true, 'startedAt': 0}).startedAt,
        isNull,
      );
      expect(DnsServerStatus.fromMap({'running': false}).startedAt, isNull);
    });
  });

  group('ServiceStatsNotifier 接入真实计数', () {
    test('applyNative 覆盖 mock 值，停止时归零', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final stats = c.read(serviceStatsProvider.notifier);
      expect(c.read(serviceStatsProvider).queries, 0);

      stats.applyNative({
        'queries': 9,
        'blocked': 4,
        'cacheHits': 6,
      }, running: true);
      final running = c.read(serviceStatsProvider);
      expect(running.queries, 9);
      expect(running.blocked, 4);
      expect(running.cacheHits, 6);
      expect(running.cacheHitRate, closeTo(6 / 9, 0.0001));

      stats.applyNative(const {}, running: false);
      expect(c.read(serviceStatsProvider).queries, 0);
    });

    test('原生启动时间决定运行时长，进程重建后不会归零', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final stats = c.read(serviceStatsProvider.notifier);

      // The UI process was recreated: nothing local remembers the start, only the service does.
      stats.applyNative(
        {'queries': 1},
        running: true,
        startedAt: DateTime.now().subtract(
          const Duration(minutes: 7, seconds: 3),
        ),
      );
      final uptime = c.read(serviceStatsProvider).uptime;
      expect(uptime.inMinutes, 7);
      expect(uptime.inSeconds % 60, closeTo(3, 2));
    });

    test('非当前数据面的同步不清空计时', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final stats = c.read(serviceStatsProvider.notifier);

      stats.applyNative(
        {'queries': 5},
        running: true,
        startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      // The other plane always answers "not running"; acting on it flashed `0秒` for a second.
      stats.applyNative(const {}, running: false, ownsStats: false);

      final kept = c.read(serviceStatsProvider);
      expect(kept.queries, 5);
      expect(kept.uptime.inMinutes, 2);
    });

    test('syncStatus 将原生 stats 写进服务统计', () async {
      final fake = FakeVpnController()
        ..statusValue = const VpnStatus(
          running: true,
          persisted: true,
          stats: {'queries': 21, 'blocked': 2, 'cacheHits': 11},
        );
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          vpnControllerProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(c.dispose);

      await c.read(powerProvider.notifier).syncStatus();
      expect(c.read(serviceStatsProvider).queries, 21);
      expect(c.read(serviceStatsProvider).cacheHits, 11);
    });
  });
}

/// The on-demand switch and the SSID table were persisted but never applied, so the tunnel kept
/// running whatever network the device joined. These pin the rule that now drives it.
void _onDemand() {
  ProviderContainer container({
    required FakeVpnController vpn,
    String? ssid,
    bool onDemand = true,
    List<MockSsidRule> rules = const [MockSsidRule(ssid: 'Home-5G')],
    String workMode = 'normal',
    bool running = false,
    String? lastSsid,
  }) {
    final store = MemoryLegacyPrefsStore({
      'diting_settings': {'app_work_mode': workMode},
      'dns_vpn_prefs': {'vpn_running': running},
      'diting_config_resources': {
        'on_demand_enabled': onDemand,
        'on_demand_last_ssid': ?lastSsid,
        'ssid_rules_json': jsonEncode([
          for (final rule in rules)
            {
              'ssid': rule.ssid,
              'cellular': rule.cellular,
              'wifi': rule.wifi,
              'delayMs': rule.delayMs,
            },
        ]),
      },
    });
    vpn.statusValue = VpnStatus(running: running, persisted: running);
    final instance = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(store),
        vpnControllerProvider.overrideWithValue(vpn),
        currentSsidReaderProvider.overrideWithValue(() async => ssid),
      ],
    );
    addTearDown(instance.dispose);
    return instance;
  }

  /// The last network the whitelist was applied to; `null` means the key is absent.
  String? readLastSsid(ProviderContainer c) =>
      c
              .read(legacyPrefsStoreProvider)
              .read('diting_config_resources', 'on_demand_last_ssid')
          as String?;

  /// Settles the asynchronous status sync `PowerNotifier.build` starts for a persisted tunnel.
  Future<void> settle(ProviderContainer instance) async {
    instance.read(powerProvider);
    await Future<void>.delayed(Duration.zero);
  }

  group('按需连接判定', () {
    test('关闭时不动隧道', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'Home-5G', onDemand: false);
      expect(
        await c.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.disabled,
      );
      expect(vpn.startCalls, 0);
      expect(vpn.stopCalls, 0);
    });

    test('无法读取 SSID 时不动隧道', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: null);
      expect(
        await c.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.unknownSsid,
      );
      expect(vpn.startCalls, 0);
      expect(vpn.stopCalls, 0);
    });

    test('服务器模式不动隧道', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'Home-5G', workMode: 'dns');
      expect(
        await c.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.serverMode,
      );
      expect(vpn.startCalls, 0);
    });

    test('匹配白名单时启动 VPN', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'Home-5G');
      expect(
        await c.read(onDemandRunnerProvider).apply(force: true),
        OnDemandOutcome.started,
      );
      expect(vpn.startCalls, 1);
      expect(c.read(powerProvider), PowerState.running);
    });

    test('已在运行时不重复启动', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'Home-5G', running: true);
      await settle(c);
      expect(c.read(powerProvider), PowerState.running);
      expect(
        await c.read(onDemandRunnerProvider).apply(force: true),
        OnDemandOutcome.alreadyRunning,
      );
      expect(vpn.startCalls, 0);
    });

    test('不在白名单时停止 VPN', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'Cafe-WiFi', running: true);
      await settle(c);
      expect(c.read(powerProvider), PowerState.running);
      expect(
        await c.read(onDemandRunnerProvider).apply(force: true),
        OnDemandOutcome.stopped,
      );
      expect(vpn.stopCalls, 1);
      expect(c.read(powerProvider), PowerState.stopped);
    });

    test('SSID 区分大小写', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'home-5g');
      expect(
        await c.read(onDemandRunnerProvider).apply(force: true),
        OnDemandOutcome.alreadyStopped,
      );
      expect(vpn.startCalls, 0);
    });

    test('未授权时报告等待系统授权', () async {
      final vpn = FakeVpnController(prepared: false);
      final c = container(vpn: vpn, ssid: 'Home-5G');
      expect(
        await c.read(onDemandRunnerProvider).apply(force: true),
        OnDemandOutcome.needsConsent,
      );
      expect(c.read(powerProvider), PowerState.starting);
      expect(vpn.startCalls, 0);
    });
  });

  /// Start and resume re-evaluate the whitelist without force; these pin the "only act on a
  /// network change" rule that keeps a manual start/stop from being overridden on every launch.
  group('启动/回前台重估', () {
    test('首次评估只记录网络，不动隧道', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'Home-5G');
      expect(
        await c.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.sameNetwork,
      );
      expect(vpn.startCalls, 0);
      expect(readLastSsid(c), 'Home-5G');
    });

    test('网络未变化时不覆盖手动状态', () async {
      final vpn = FakeVpnController();
      final stopped = container(vpn: vpn, ssid: 'Home-5G', lastSsid: 'Home-5G');
      expect(
        await stopped.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.sameNetwork,
      );
      expect(vpn.startCalls, 0);

      final running = container(
        vpn: vpn,
        ssid: 'Home-5G',
        lastSsid: 'Home-5G',
        running: true,
      );
      await settle(running);
      expect(
        await running.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.sameNetwork,
      );
      expect(vpn.stopCalls, 0);
    });

    test('网络切换到白名单内时启动并记录新网络', () async {
      final vpn = FakeVpnController();
      final c = container(vpn: vpn, ssid: 'Home-5G', lastSsid: 'Cafe-WiFi');
      expect(
        await c.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.started,
      );
      expect(vpn.startCalls, 1);
      expect(readLastSsid(c), 'Home-5G');
      expect(
        await c.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.sameNetwork,
      );
      expect(vpn.startCalls, 1);
    });

    test('网络切换到白名单外时停止', () async {
      final vpn = FakeVpnController();
      final c = container(
        vpn: vpn,
        ssid: 'Cafe-WiFi',
        lastSsid: 'Home-5G',
        running: true,
      );
      await settle(c);
      expect(
        await c.read(onDemandRunnerProvider).apply(),
        OnDemandOutcome.stopped,
      );
      expect(vpn.stopCalls, 1);
      expect(readLastSsid(c), 'Cafe-WiFi');
    });
  });
}
