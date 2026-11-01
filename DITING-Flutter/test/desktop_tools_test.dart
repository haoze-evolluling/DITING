// Desktop tools branch, diagnosis half (docs/development/flutter-desktop-ui.md step 4): the port
// probe and its autofix. The probe runs on demand; both calls adopt the service's answer.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/data/api/desktop_tools_models.dart';
import 'package:diting/desktop/pages/tools/desktop_tools_page.dart';
import 'package:diting/desktop/pages/tools/widgets/port_diagnosis_card.dart';
import 'package:diting/routes/branches.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpTools(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(initialLocation: Routes.tools),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopToolsPage)).l10n;

  Finder inCard(Finder matching) =>
      find.descendant(of: find.byType(PortDiagnosisCard), matching: matching);

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> clearMessages(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  test('缺字段按不可用解析，冲突列表为空', () {
    final result = DesktopPortCheck.fromJson(const {});
    expect(result.available, isFalse);
    expect(result.conflicts, isEmpty);
    expect(result.canRepair, isFalse);

    final parsed = DesktopPortCheck.fromJson(const {
      'available': false,
      'hasICS': true,
      'canAutofix': true,
      'conflicts': [
        {'port': 53, 'protocol': 'TCP', 'pid': 42},
      ],
    });
    expect(parsed.conflicts.single.port, 53);
    expect(parsed.conflicts.single.isSelf, isFalse);
    expect(parsed.canRepair, isTrue);
  });

  testWidgets('未检测时只给出提示，不显示冲突', (tester) async {
    await pumpTools(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopToolsPortIdle), findsOneWidget);
    expect(find.text(l10n.desktopToolsFix), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检测后显示冲突进程与诊断文本', (tester) async {
    await pumpTools(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byTooltip(l10n.desktopToolsCheck)));
    expect(find.text(l10n.desktopToolsPortConflict), findsWidgets);
    expect(find.text('svchost.exe · PID 1234 · 0.0.0.0:53'), findsOneWidget);
    expect(find.text('UDP :53'), findsOneWidget);
    expect(find.text(l10n.desktopToolsSystemListener), findsOneWidget);
    expect(
      find.text('停止 Internet Connection Sharing 后即可释放端口'),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopToolsFix), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('端口可用时不提供修复按钮', (tester) async {
    await pumpTools(
      tester,
      backend: FakeDesktopBackend(
        portCheck: portCheckPayload(
          available: true,
          hasICS: false,
          canAutofix: false,
          diagnostic: '',
        ),
      ),
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byTooltip(l10n.desktopToolsCheck)));
    expect(find.text(l10n.desktopToolsPortOk), findsWidgets);
    expect(find.text(l10n.desktopToolsFix), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一键修复需确认，提交 startDNS=false 并采用修复结果', (tester) async {
    final backend = await pumpTools(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byTooltip(l10n.desktopToolsCheck)));
    await tapAt(tester, inCard(find.text(l10n.desktopToolsFix)));
    expect(find.text(l10n.desktopToolsFixTitle), findsOneWidget);
    await tapAt(tester, find.text(l10n.desktopToolsFix).last);

    expect(backend.autofixUpdates.single, {'startDNS': false});
    expect(find.text(l10n.desktopToolsFixed), findsOneWidget);
    expect(find.text(l10n.desktopToolsFix), findsNothing);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('修复被拒时说明原因并保留冲突信息', (tester) async {
    final backend = FakeDesktopBackend()..rejectWrites = true;
    await pumpTools(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byTooltip(l10n.desktopToolsCheck)));
    await tapAt(tester, inCard(find.text(l10n.desktopToolsFix)));
    await tapAt(tester, find.text(l10n.desktopToolsFix).last);

    expect(
      find.text(l10n.desktopToolsFailed('write rejected')),
      findsWidgets,
    );
    expect(find.text('UDP :53'), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗不横向溢出', (tester) async {
    await pumpTools(tester, size: const Size(390, 844));
    final l10n = l10nOf(tester);
    await tapAt(tester, inCard(find.byTooltip(l10n.desktopToolsCheck)));
    expect(find.byType(PortDiagnosisCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
