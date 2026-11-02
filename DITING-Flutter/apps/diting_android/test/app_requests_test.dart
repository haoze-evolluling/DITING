import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/pages/observability/requests_page.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_host.dart';

void main() {
  group('按包名读取请求', () {
    late Database db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE dns_log (id INTEGER PRIMARY KEY, timestamp INTEGER, '
        'queryName TEXT, queryType INTEGER, result TEXT, cached INTEGER, '
        'message TEXT, packageName TEXT, blockSubscriptionId INTEGER)',
      );
      await db.execute(
        'CREATE TABLE http_request_log (id INTEGER PRIMARY KEY, '
        'timestamp INTEGER, packageName TEXT, authority TEXT, protocol TEXT, '
        'outcome TEXT, matchedRule TEXT, blockSubscriptionId INTEGER)',
      );
      var id = 0;
      for (final package in ['com.a', 'com.a', 'com.ab', null, '']) {
        id++;
        await db.insert('dns_log', {
          'id': id,
          'timestamp': id,
          'queryName': 'q$id.example',
          'queryType': 1,
          'result': 'PASSED',
          'cached': 0,
          'packageName': package,
        });
      }
      for (final package in ['com.a', 'com.b', '']) {
        id++;
        await db.insert('http_request_log', {
          'id': id,
          'timestamp': id,
          'packageName': package,
          'authority': 'h$id.example',
          'protocol': 'h2',
          'outcome': 'allowed',
        });
      }
    });

    tearDown(() => db.close());

    test('包名精确匹配，不会把前缀相同的应用混进来', () async {
      final dns = await DnsQueryRepository(db).recent(packageName: 'com.a');
      final http = await HttpRequestRepository(db).recent(packageName: 'com.a');
      expect(dns.map((row) => row.packageName), ['com.a', 'com.a']);
      expect(http.map((row) => row.packageName), ['com.a']);
    });

    test('按包名计数时跳过没有归属的记录', () async {
      expect(await DnsQueryRepository(db).countByPackage(), {
        'com.a': 2,
        'com.ab': 1,
      });
      expect(await HttpRequestRepository(db).countByPackage(), {
        'com.a': 1,
        'com.b': 1,
      });
    });
  });

  group('按应用查看页', () {
    Future<void> pump(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            requestAppCountsProvider.overrideWith(
              (ref) async => const [
                AppRequestCount(packageName: 'com.example.browser', count: 12),
                AppRequestCount(packageName: 'com.example.ads', count: 3),
              ],
            ),
            appRequestFeedProvider.overrideWith(
              (ref, packageName) async => RequestFeed(
                items: [
                  ObservedRequest.fromHttp(
                    HttpRequestRecord(
                      id: 1,
                      timestamp: 1,
                      packageName: packageName,
                      protocol: 'h2',
                      outcome: 'allowed',
                      authority: '$packageName.host',
                    ),
                  ),
                ],
                hasMore: false,
              ),
            ),
          ],
          child: AppHost(child: page),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('列出有请求记录的应用及请求次数', (tester) async {
      await pump(tester, const RequestAppsPage());
      expect(tester.takeException(), isNull);
      expect(find.text('com.example.browser'), findsOneWidget);
      expect(find.text('12 次请求'), findsOneWidget);
      expect(find.text('3 次请求'), findsOneWidget);
    });

    testWidgets('单个应用页只显示该应用的请求', (tester) async {
      await pump(tester, const AppRequestsPage(packageName: 'com.example.ads'));
      expect(tester.takeException(), isNull);
      expect(find.text('com.example.ads.host'), findsOneWidget);
      expect(find.textContaining('共 1 条'), findsOneWidget);
    });
  });
}
