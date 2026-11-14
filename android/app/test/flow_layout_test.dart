// U9/N4: the real-time flow page splits into an app list + the selected app's connections on a
// tablet, and keeps the grouped single column on a phone.

import 'package:diting_android/data/native/flow_bridge.dart';
import 'package:diting_android/pages/network/flow_page.dart';
import 'package:diting_android/state/flow_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

FlowRow _row(String pkg, String domain, int seq) => FlowRow(
  protocol: 'tcp',
  srcIp: '10.0.0.2',
  srcPort: 40000 + seq,
  dstIp: '93.184.216.$seq',
  dstPort: 443,
  uid: 10000,
  package: pkg,
  domain: domain,
  upBytes: 100,
  downBytes: 200,
  status: 'active',
  firstSeenMs: seq,
  lastSeenMs: seq,
  seq: seq,
);

class _FakeFlowNotifier extends FlowViewNotifier {
  _FakeFlowNotifier(this.rows);

  final List<FlowRow> rows;

  @override
  FlowViewState build() => FlowViewState(
    rowsMap: {for (final row in rows) row.key: row},
  );

  @override
  Future<void> refresh({bool full = false}) async {}
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        flowViewProvider.overrideWith(
          () => _FakeFlowNotifier([
            _row('Alpha', 'alpha.example', 1),
            _row('Beta', 'beta.example', 2),
          ]),
        ),
      ],
      child: AppHost(
        size: size,
        isMobile: size.width < 720,
        child: const FlowPage(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('平板宽度：应用列表与所选应用连接并排', (tester) async {
    await _pump(tester, const Size(1200, 900));

    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);
    // The most recent connection's app is selected first (Beta, seq 2).
    expect(find.text('beta.example'), findsOneWidget);
    expect(find.text('alpha.example'), findsNothing);

    await tester.tap(find.text('Alpha').first);
    await tester.pump();
    expect(find.text('alpha.example'), findsOneWidget);
    expect(find.text('beta.example'), findsNothing);
    expect(tester.takeException(), isNull);

    // Unmount so the page's refresh timer is cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('手机宽度：按应用分组单列', (tester) async {
    await _pump(tester, const Size(400, 800));

    expect(find.text('alpha.example'), findsOneWidget);
    expect(find.text('beta.example'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
