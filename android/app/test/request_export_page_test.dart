import 'package:diting_android/data/export/request_log_csv_exporter.dart';
import 'package:diting_android/pages/observability/request_export_page.dart';
import 'package:diting_android/state/request_export_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

class _NormalMode extends WorkModeNotifier {
  @override
  AppWorkMode build() => AppWorkMode.normal;
}

void main() {
  Future<void> pump(WidgetTester tester, RequestLogExportRunner runner) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requestLogExportRunnerProvider.overrideWithValue(runner),
          workModeProvider.overrideWith(_NormalMode.new),
        ],
        child: const AppHost(child: RequestLogExportPage()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('渲染导出配置并给出导出结果提示', (tester) async {
    var calls = 0;
    await pump(tester, (options) async {
      calls++;
      return const RequestLogExportOutcome.saved(
        RequestLogExportResult(count: 3, truncated: false),
        'x.csv',
      );
    });
    expect(tester.takeException(), isNull);
    expect(find.text('导出请求日志'), findsOneWidget);
    expect(find.text('时间范围'), findsOneWidget);
    expect(find.text('全部时间'), findsOneWidget);
    expect(find.text('筛选条件'), findsOneWidget);
    expect(find.text('来源'), findsWidgets);
    expect(find.text('全部应用'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('导出 CSV'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('已导出 3 条记录'), findsOneWidget);
  });

  testWidgets('条数越界时提示并禁用导出', (tester) async {
    await pump(
      tester,
      (options) async => const RequestLogExportOutcome.empty(),
    );
    await tester.scrollUntilVisible(
      find.byType(TextFormField),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('请输入 1–50000 之间的条数'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('请输入 1–50000 之间的条数'), findsOneWidget);
    final button = tester.widget<TonalButton>(find.byType(TonalButton));
    expect(button.onPressed, isNull);
  });
}
