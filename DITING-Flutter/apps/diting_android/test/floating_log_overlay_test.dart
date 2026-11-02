import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/overlay/floating_log_data.dart';
import 'package:diting_android/overlay/floating_log_main.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeSource extends FloatingLogSource {
  _FakeSource(this.items);

  final List<ObservedRequest> items;
  String? lastQuery;

  @override
  Future<FloatingLogSnapshot> load({
    String query = '',
    RequestSource source = RequestSource.all,
  }) async {
    lastQuery = query;
    return FloatingLogSnapshot(items: items);
  }

  @override
  Future<int> blockedSince(int since) async => 0;
}

/// Records window calls instead of resizing a real overlay.
class _FakeWindow extends FloatingLogWindowChannel {
  final calls = <String>[];

  /// Stands in for the native resize, which the test surface does not do by itself.
  void Function(Size size)? onResize;

  @override
  Future<void> setExpanded(
    bool expanded, {
    Size size = Size.zero,
    double dragStrip = 0,
  }) async {
    calls.add(expanded ? 'expand' : 'collapse');
    onResize?.call(expanded ? size : const Size.square(56));
  }

  @override
  Future<void> setFocusable(bool value) async => calls.add('focus:$value');

  @override
  Future<void> openApp() async => calls.add('openApp');

  @override
  Future<void> dismiss() async => calls.add('dismiss');

  @override
  void onBack(VoidCallback handler) {}
}

ObservedRequest _request(String key, String title, RequestStatus status) =>
    ObservedRequest(
      key: key,
      timestamp: DateTime.now().millisecondsSinceEpoch - 1000,
      source: RequestSource.dns,
      status: status,
      title: title,
    );

void main() {
  testWidgets('悬浮窗日志：展开面板、按状态筛选、清空仅影响显示', (tester) async {
    final window = _FakeWindow();
    void resize(Size size) =>
        tester.view.physicalSize = size * tester.view.devicePixelRatio;
    window.onResize = resize;
    resize(const Size.square(56));
    addTearDown(tester.view.reset);
    final source = _FakeSource([
      _request('dns-1', 'ads.example.com', RequestStatus.blocked),
      _request('dns-2', 'api.example.com', RequestStatus.passed),
    ]);
    await tester.pumpWidget(
      FloatingLogApp(
        settings: LegacySettings(
          MemoryLegacyPrefsStore({
            LegacySettings.uiContainer: {'app_language_mode': 'chinese'},
          }),
        ),
        source: source,
        window: window,
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed: only the bubble.
    expect(find.text('ads.example.com'), findsNothing);
    await tester.tap(find.bySemanticsLabel('打开悬浮窗日志'));
    await tester.pumpAndSettle();
    expect(window.calls, ['expand']);
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.text('api.example.com'), findsOneWidget);

    // The blocked chip narrows the list to the blocked row.
    await tester.tap(find.text(RequestStatus.blocked.label).first);
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.text('api.example.com'), findsNothing);

    // Tapping a row unfolds its details in place.
    await tester.tap(find.text('ads.example.com'));
    await tester.pumpAndSettle();
    expect(find.text('复制域名'), findsOneWidget);

    // Clear hides the rows already shown; the source is never asked to delete anything.
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空列表'));
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsNothing);
    expect(find.text('列表已清空，新的请求会继续出现。'), findsOneWidget);

    // Minimise returns to the bubble.
    await tester.tap(find.byTooltip('收起为悬浮球'));
    await tester.pumpAndSettle();
    expect(window.calls.last, 'collapse');
    expect(find.bySemanticsLabel('打开悬浮窗日志'), findsOneWidget);

    // Stop the polling timers before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
