// Desktop hub time plan (desktop parity): the switch, the named
// windows and the service's "active now" state. Windows are a local draft; only the save button
// posts them, and the page then shows what the service re-reads.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/data/api/desktop_schedule_models.dart';
import 'package:diting_desktop/pages/hub/desktop_schedule_page.dart';
import 'package:diting_desktop/pages/hub/widgets/schedule_editor.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpSchedule(
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
        child: const DesktopApp(initialLocation: DesktopSchedulePage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopSchedulePage)).l10n;

  Finder inEditor(Finder matching) =>
      find.descendant(of: find.byType(ScheduleEditor), matching: matching);

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

  test('缺字段按零值解析，未知星期被丢弃，空时刻不算完整窗口', () {
    final row = DesktopSchedule.fromJson(const {
      'id': 's1',
      'weekdays': ['mon', 'bogus', 'sun'],
      'start': '22:00',
    });
    expect(row.weekdays, ['mon', 'sun']);
    expect(row.end, isEmpty);
    expect(row.isComplete, isFalse);
    expect(row.copyWith(end: '06:00').isComplete, isTrue);

    final config = DesktopScheduleConfig.fromJson(const {
      'enabled': true,
      'schedules': [
        {'id': 'a', 'enabled': true, 'start': '08:00', 'end': '18:00'},
        {'id': 'b', 'enabled': false, 'start': '20:00', 'end': '22:00'},
      ],
    });
    expect(config.enabled, isTrue);
    expect(config.enabledCount, 1);
    expect(config.toJson()['schedules'], hasLength(2));
    expect(DesktopScheduleConfig.fromJson(const {}).active, isTrue);
  });

  testWidgets('未启用时只显示开关与状态徽标', (tester) async {
    await pumpSchedule(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopScheduleBadgeOff), findsOneWidget);
    expect(
      tester.widget<DashboardSwitch>(find.byType(DashboardSwitch)).value,
      isFalse,
    );
    expect(find.byType(ScheduleEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('启用后编辑窗口并保存整份计划', (tester) async {
    final backend = await pumpSchedule(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byType(DashboardSwitch));
    expect(find.byType(ScheduleEditor), findsOneWidget);

    await tapAt(tester, find.text(l10n.desktopScheduleAdd));
    final fields = inEditor(find.byType(TextFormField));
    expect(fields, findsNWidgets(3));

    await tester.enterText(fields.at(0), '夜间放行');
    await tester.enterText(fields.at(1), '22:00');
    await tester.enterText(fields.at(2), '06:00');
    await tapAt(tester, find.text(l10n.desktopWeekdayMon));
    await tapAt(tester, find.text(l10n.desktopScheduleSave).first);

    final update = backend.scheduleUpdates.single;
    expect(update['enabled'], isTrue);
    final rows = update['schedules'] as List;
    expect(rows, hasLength(1));
    expect(rows.single, {
      'id': '',
      'name': '夜间放行',
      'enabled': true,
      'weekdays': ['mon'],
      'start': '22:00',
      'end': '06:00',
    });
    expect(find.text(l10n.desktopScheduleSaved), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有时刻的窗口不提交，空计划也照常保存开关', (tester) async {
    final backend = await pumpSchedule(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byType(DashboardSwitch));
    await tapAt(tester, find.text(l10n.desktopScheduleAdd));
    final fields = inEditor(find.byType(TextFormField));
    await tester.enterText(fields.at(1), '');
    await tester.enterText(fields.at(2), '');
    await tapAt(tester, find.text(l10n.desktopScheduleSave).first);

    final update = backend.scheduleUpdates.single;
    expect(update['enabled'], isTrue);
    expect(update['schedules'], isEmpty);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务返回的计划显示在编辑器里', (tester) async {
    await pumpSchedule(
      tester,
      backend: FakeDesktopBackend(
        schedule: schedulePayload(
          enabled: true,
          schedules: const [
            {
              'id': 's1',
              'name': '工作时间',
              'enabled': true,
              'weekdays': ['mon', 'tue'],
              'start': '09:00',
              'end': '18:00',
            },
          ],
          active: false,
        ),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopScheduleBadgePaused), findsOneWidget);
    final fields = inEditor(find.byType(TextFormField));
    expect(tester.widget<TextFormField>(fields.at(0)).controller?.text, '工作时间');
    expect(tester.widget<TextFormField>(fields.at(1)).controller?.text, '09:00');
    expect(tester.widget<TextFormField>(fields.at(2)).controller?.text, '18:00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存被拒时说明原因', (tester) async {
    final backend = await pumpSchedule(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, find.byType(DashboardSwitch));
    await tapAt(tester, find.text(l10n.desktopScheduleSave).first);

    expect(
      find.text(l10n.desktopScheduleSaveFailed('write rejected')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下窗口编辑不横向溢出', (tester) async {
    await pumpSchedule(
      tester,
      size: const Size(390, 844),
      backend: FakeDesktopBackend(
        schedule: schedulePayload(
          enabled: true,
          schedules: const [
            {
              'id': 's1',
              'name': '工作时间',
              'enabled': true,
              'weekdays': [],
              'start': '09:00',
              'end': '18:00',
            },
          ],
        ),
      ),
    );
    expect(find.byType(ScheduleEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
