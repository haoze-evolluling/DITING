part of 'native_bridge_test.dart';

/// Guards the one-shot contract of `consumeStartRequest`: the native side clears the extra when
/// read, so the tile must never be able to start a tunnel twice from one tap.
void _tileBridge() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(tileChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockResult(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  test('读取 native 的一次性启动请求', () async {
    mockResult((call) => call.method == 'consumeStartRequest' ? true : null);
    expect(await TileBridge().consumeStartRequest(), isTrue);
  });

  test('无请求时为 false', () async {
    mockResult((_) => false);
    expect(await TileBridge().consumeStartRequest(), isFalse);
  });

  test('通道缺失（桌面端）降级为 false', () async {
    // No mock handler installed at all: the call throws MissingPluginException.
    expect(await TileBridge().consumeStartRequest(), isFalse);
  });

  test('native 报错降级为 false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'boom'),
        );
    expect(await TileBridge().consumeStartRequest(), isFalse);
  });
}

/// Imported fonts are the only non-system faces now that the bundle ships none, so the bridge
/// contract and the stored shape both have to survive a round trip.
void _fontRepository() {
  group('FontPickResult.fromMap', () {
    test('成功时带上路径、名称与大小', () {
      final result = FontPickResult.fromMap({
        'path': '/data/user/0/com.haoze.diting/files/fonts/abc.ttf',
        'name': 'Inter-Regular.ttf',
        'bytes': 20480,
        'cancelled': false,
      });
      expect(result.isOk, isTrue);
      expect(result.path, endsWith('abc.ttf'));
      expect(result.name, 'Inter-Regular.ttf');
      expect(result.bytes, 20480);
    });

    test('原生报错时透传原因且不视为成功', () {
      final result = FontPickResult.fromMap({'error': '只支持 TTF / OTF 字体文件'});
      expect(result.isOk, isFalse);
      expect(result.error, '只支持 TTF / OTF 字体文件');
    });

    test('无通道的降级结果给出可读原因', () {
      final result = FontPickResult.unavailable();
      expect(result.isOk, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('已导入字体的存取', () {
    late MemoryLegacyPrefsStore store;

    setUp(() => store = MemoryLegacyPrefsStore());

    test('写入后按原样读回，路径与族名都不丢', () {
      final settings = LegacySettings(store);
      settings.setImportedFonts(const [
        ImportedFont(
          family: 'Inter-Regular',
          label: 'Inter-Regular',
          path: '/fonts/abc.ttf',
        ),
      ]);

      final restored = LegacySettings(store).importedFonts;
      expect(restored, hasLength(1));
      expect(restored.single.family, 'Inter-Regular');
      expect(restored.single.path, '/fonts/abc.ttf');
    });

    test('损坏的 JSON 与缺字段的条目都被忽略', () {
      store.putString('dns_vpn_prefs', 'app_imported_fonts', 'not json');
      expect(LegacySettings(store).importedFonts, isEmpty);

      store.putString(
        'dns_vpn_prefs',
        'app_imported_fonts',
        '[{"family":"","path":"/x.ttf"},{"label":"无路径"},'
            '{"family":"Ok","path":"/ok.ttf","label":"Ok"}]',
      );
      final fonts = LegacySettings(store).importedFonts;
      expect(fonts, hasLength(1));
      expect(fonts.single.family, 'Ok');
    });
  });
}

/// The troubleshooting card is the only place a silent "no logs at all" becomes visible, so the
/// mapping from the native payload has to keep three cases apart: fine, dropping, and unopenable.
void _dbHealthBridge() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(dbHealthChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockResult(Map<String, Object?> payload) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => payload);
  }

  test('连接正常时如实给出日志模式与 busy 超时', () async {
    mockResult({
      'droppedRows': 0,
      'openFailures': 0,
      'lastCause': '',
      'probeOk': true,
      'probeAbsent': false,
      'probeJournalMode': 'wal',
      'probeBusyTimeoutMs': 5000,
      'probeCause': '',
    });
    final health = await DbHealthBridge().status();
    expect(health.healthy, isTrue);
    expect(health.probeJournalMode, 'wal');
    expect(health.probeBusyTimeoutMs, 5000);
  });

  test('有丢弃或打开失败时不算健康，并透传原因', () async {
    mockResult({
      'droppedRows': 12,
      'openFailures': 3,
      'lastCause': 'SQLiteDatabaseLockedException: database is locked',
      'probeOk': false,
      'probeAbsent': false,
      'probeCause': 'SQLiteException: boom',
    });
    final health = await DbHealthBridge().status();
    expect(health.healthy, isFalse);
    expect(health.droppedRows, 12);
    expect(health.openFailures, 3);
    expect(health.lastCause, contains('database is locked'));
  });

  test('计数为零但探针打不开库，也要报不健康', () async {
    mockResult({
      'droppedRows': 0,
      'openFailures': 0,
      'probeOk': false,
      'probeAbsent': false,
      'probeCause': 'SQLiteException: unknown error (code 0 SQLITE_OK)',
    });
    final health = await DbHealthBridge().status();
    expect(health.healthy, isFalse);
    expect(health.probeCause, contains('SQLITE_OK'));
  });

  test('丢弃按原因拆分透传，最近一次丢弃带表名', () async {
    mockResult({
      'droppedRows': 7,
      'droppedByReason': {'overflow': 5, 'tableMissing': 2, 'closed': 0},
      'lastDrop': 'dns_log:overflow',
      'openFailures': 0,
      'probeOk': true,
    });
    final health = await DbHealthBridge().status();
    expect(health.healthy, isFalse);
    expect(health.droppedByReason, {
      'overflow': 5,
      'tableMissing': 2,
      'closed': 0,
    });
    expect(health.lastDrop, 'dns_log:overflow');
  });

  test('首次安装还没有库文件时不算故障', () async {
    mockResult({
      'droppedRows': 0,
      'openFailures': 0,
      'probeOk': false,
      'probeAbsent': true,
      'probeCause': 'database file missing',
    });
    expect((await DbHealthBridge().status()).healthy, isTrue);
  });

  test('通道缺失（桌面端）降级为不可读而不是抛异常', () async {
    final health = await DbHealthBridge().status();
    expect(health.healthy, isTrue);
    expect(health.probeJournalMode, isEmpty);
  });
}
