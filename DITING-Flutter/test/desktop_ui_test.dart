import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/desktop_models.dart';
import 'package:diting/desktop/data/desktop_backend.dart';
import 'package:diting/desktop/data/desktop_native_bridge.dart';
import 'package:diting/desktop/state/desktop_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDesktop(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    FakeDesktopBackend? backend,
    String initialLocation = '/overview',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopPreferencesProvider.overrideWithValue(preferences),
          desktopBackendProvider.overrideWithValue(
            backend ?? FakeDesktopBackend(),
          ),
          desktopNativeBridgeProvider.overrideWithValue(FakeNativeBridge()),
        ],
        child: DitingDesktopApp(initialLocation: initialLocation),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('宽屏总览展示真实状态并可切换解析开关', (tester) async {
    final backend = FakeDesktopBackend();
    await pumpDesktop(tester, backend: backend);

    expect(find.text('网络保护已开启'), findsOneWidget);
    expect(find.text('实时查询速率'), findsOneWidget);
    expect(find.textContaining('12.5'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(backend.running, isFalse);
    expect(find.text('谛听已准备就绪'), findsOneWidget);
  });

  testWidgets('导航进入模块骨架与外观设置', (tester) async {
    await pumpDesktop(tester);

    await tester.tap(find.text('解析').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('让每一次解析更快、更可靠'), findsOneWidget);
    expect(find.text('待接入'), findsWidgets);

    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('外观与主题'), findsOneWidget);
    await tester.tap(find.text('深色'));
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('窄屏使用底部导航且页面无横向溢出', (tester) async {
    await pumpDesktop(
      tester,
      size: const Size(600, 900),
      initialLocation: '/settings',
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('外观与主题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('状态 JSON 只映射 UI 所需字段并保留真实比例语义', () {
    final snapshot = sampleSnapshot();
    expect(snapshot.dns.running, isTrue);
    expect(snapshot.dns.modeLabel, '智能优选');
    expect(snapshot.successRate, closeTo(.98, .0001));
    expect(snapshot.cache!.hitRatio, .625);
    expect(snapshot.filter!.blockRate, 18.2);
  });
}

class FakeDesktopBackend implements DesktopBackend {
  bool running = true;
  bool takeover = true;

  @override
  Future<DesktopSnapshot> getSnapshot() async =>
      sampleSnapshot(running: running, takeover: takeover);

  @override
  Future<void> setDnsRunning(bool value) async => running = value;

  @override
  Future<void> setTakeover(bool value) async => takeover = value;
}

class FakeNativeBridge implements DesktopNativeBridge {
  @override
  bool get isAvailable => false;

  @override
  Future<String> getPlatform() async => 'windows';
  @override
  Future<CoreServiceStatus> getCoreServiceStatus() async =>
      const CoreServiceStatus(
        installed: true,
        running: true,
        stateText: '运行中',
        canInstall: false,
        message: '',
      );
  @override
  Future<bool> isAutoStartEnabled() async => false;
  @override
  Future<bool> setAutoStart(bool enabled) async => enabled;
  @override
  Future<String> installAndStartCoreService() async => 'ok';
  @override
  Future<String> restartCoreService() async => 'ok';
  @override
  Future<String> runEmergencyRestore() async => 'ok';
  @override
  Future<String> startCoreService() async => 'ok';
  @override
  Future<String> stopCoreService() async => 'ok';
}

DesktopSnapshot sampleSnapshot({bool running = true, bool takeover = true}) {
  return DesktopSnapshot.fromJson({
    'version': '1.4.3',
    'uptimeSeconds': 7384,
    'dns': {
      'running': running,
      'mode': 'smart_prediction',
      'listenAddresses': ['127.0.0.1:53'],
      'allowLAN': false,
      'upstreams': [
        {
          'id': 'ali',
          'protocol': 'DOH',
          'url': 'https://dns.alidns.com/dns-query',
          'active': true,
          'avgLatencyMs': 12.5,
        },
      ],
    },
    'takeover': {
      'active': takeover,
      'adapters': takeover
          ? [
              {'id': 'ethernet'},
            ]
          : [],
    },
    'metrics': {
      'totalQueries': 1000,
      'successQueries': 980,
      'failedQueries': 20,
      'avgLatencyMs': 16.8,
      'qps': 12.5,
    },
    'cache': {
      'enabled': true,
      'hitRatio': .625,
      'entryCount': 320,
      'maxEntries': 1000,
    },
    'filter': {
      'enabled': true,
      'totalRules': 45678,
      'activeLists': 4,
      'blockedQueries': 182,
      'blockRate': 18.2,
      'paused': false,
    },
  });
}
