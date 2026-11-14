// U6/U9: the app-insights page shows report cards beside the selected app's connection map on a
// tablet, and keeps the single-column scroll on a phone.

import 'package:diting_android/data/network/app_insights.dart';
import 'package:diting_android/pages/network/app_insights_page.dart';
import 'package:diting_android/state/app_insights_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

AppReport _report(String label, int bytes) => AppReport(
  appLabel: label,
  connectionCount: 2,
  blockedCount: 0,
  upBytes: bytes ~/ 2,
  downBytes: bytes ~/ 2,
  topDomains: const [],
);

AppConnectionGroup _group(String label, String domain) => AppConnectionGroup(
  appLabel: label,
  domains: [
    DomainSummary(
      domain: domain,
      connectionCount: 2,
      totalBytes: 2048,
      blockedCount: 0,
    ),
  ],
);

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appReportsProvider.overrideWith(
          (ref) => [_report('Alpha', 4096), _report('Beta', 2048)],
        ),
        connectionMapProvider.overrideWith(
          (ref) => [
            _group('Alpha', 'alpha.example'),
            _group('Beta', 'beta.example'),
          ],
        ),
      ],
      child: AppHost(
        size: size,
        isMobile: size.width < 720,
        child: const AppInsightsPage(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('平板宽度：报告卡与所选应用的连接地图并排', (tester) async {
    await _pump(tester, const Size(1200, 900));

    // Both report cards are in the left pane.
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);
    // The right pane shows only the selected app's map.
    expect(find.text('alpha.example'), findsOneWidget);
    expect(find.text('beta.example'), findsNothing);

    await tester.tap(find.text('Beta').first);
    await tester.pump();
    expect(find.text('beta.example'), findsOneWidget);
    expect(find.text('alpha.example'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度：单列展示全部连接地图', (tester) async {
    await _pump(tester, const Size(400, 800));

    expect(find.text('alpha.example'), findsOneWidget);
    expect(find.text('beta.example'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
