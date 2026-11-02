// The desktop client is the only path between the window and the local service, so its parsing and
// its failure modes are worth pinning: an error that silently turns into zeros would paint a
// healthy-looking dashboard over a broken backend.

import 'dart:convert';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  DesktopApiClient clientOf(MockClient mock) =>
      DesktopApiClient(httpClient: mock);

  test('解析状态快照的每个字段', () async {
    final backend = FakeDesktopBackend();
    final status = await backend.client().status();

    expect(status.version, '2.2.9');
    expect(status.pid, 4242);
    expect(status.uptime, const Duration(seconds: 90061));
    expect(status.dns.running, isTrue);
    expect(status.dns.listenSummary, '127.0.0.1:5353');
    expect(status.dns.allowLan, isTrue);
    expect(status.takeover.active, isTrue);
    expect(status.takeover.adapters, ['eth0']);
    expect(status.metrics.total, 12345);
    expect(status.metrics.success, 12000);
    expect(status.metrics.failed, 345);
    expect(status.metrics.averageLatencyMs, 12.4);
    expect(status.metrics.qps, 7.5);
    expect(status.cache.hitRatio, closeTo(0.6667, 0.0001));
    expect(status.cache.entries, 640);
    expect(status.cache.evictions, 12);
    expect(status.filter.rules, 2048);
    expect(status.filter.blocked, 987);
    expect(status.filter.paused, isFalse);
  });

  test('缺字段的快照按零值解析而不是抛错', () async {
    final client = clientOf(
      MockClient((_) async => http.Response(jsonEncode(apiEnvelope({})), 200)),
    );

    final status = await client.status();
    expect(status.version, isEmpty);
    expect(status.uptime, Duration.zero);
    expect(status.dns.running, isFalse);
    expect(status.dns.listenSummary, isEmpty);
    expect(status.cache.entries, 0);
    expect(status.filter.rules, 0);
  });

  test('后台服务状态解析 installed / running / autoStart', () async {
    final backend = FakeDesktopBackend(
      service: servicePayload(installed: true, running: false, autoStart: null),
    );
    final service = await backend.client().serviceStatus();

    expect(service.installed, isTrue);
    expect(service.running, isFalse);
    expect(service.autoStart, isNull);
  });

  test('401 是鉴权问题，而不是服务不可达', () async {
    final backend = FakeDesktopBackend(statusCode: 401);
    await expectLater(
      backend.client().status(),
      throwsA(
        isA<DesktopApiException>()
            .having((error) => error.unauthorized, 'unauthorized', isTrue)
            .having((error) => error.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('401 把服务端原因带进异常消息', () async {
    final client = clientOf(
      MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({'success': false, 'error': '会话已过期，请重新登录'}),
          ),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      client.status(),
      throwsA(
        isA<DesktopApiException>()
            .having((error) => error.unauthorized, 'unauthorized', isTrue)
            .having((error) => error.message, 'message', '会话已过期，请重新登录'),
      ),
    );
  });

  test('401 回调只在非登录接口触发', () async {
    var fired = 0;
    DesktopApiClient withCallback(MockClient mock) => DesktopApiClient(
      httpClient: mock,
      onUnauthorized: () => fired++,
    );
    final unauthorized = MockClient(
      (_) async => http.Response(
        jsonEncode({'success': false, 'error': 'unauthorized'}),
        401,
      ),
    );

    await expectLater(
      withCallback(unauthorized).status(),
      throwsA(isA<DesktopApiException>()),
    );
    expect(fired, 1);

    await expectLater(
      withCallback(
        unauthorized,
      ).signIn(username: 'admin', password: 'wrong'),
      throwsA(isA<DesktopApiException>()),
    );
    expect(fired, 1);
  });

  test('错误信封的 error 字段成为异常消息', () async {
    final client = clientOf(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'success': false, 'error': 'dns listener busy'}),
          500,
        ),
      ),
    );

    await expectLater(
      client.stopDns(),
      throwsA(
        isA<DesktopApiException>().having(
          (error) => error.message,
          'message',
          contains('dns listener busy'),
        ),
      ),
    );
  });

  test('非 JSON 响应不会假装成功', () async {
    final client = clientOf(
      MockClient((_) async => http.Response('<html>gateway</html>', 502)),
    );

    await expectLater(client.status(), throwsA(isA<DesktopApiException>()));
  });

  test('连接失败转成 DesktopApiException', () async {
    final client = clientOf(
      MockClient((request) async {
        throw http.ClientException('connection refused', request.url);
      }),
    );

    await expectLater(
      client.status(),
      throwsA(
        isA<DesktopApiException>().having(
          (error) => error.message,
          'message',
          contains('connection refused'),
        ),
      ),
    );
  });

  test('暂停拦截带上 paused 与 durationSec', () async {
    late String body;
    final client = clientOf(
      MockClient((request) async {
        body = request.body;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await client.setFilterPaused(true);
    expect(jsonDecode(body), {'paused': true, 'durationSec': 0});

    await client.setFilterPaused(false);
    expect(jsonDecode(body), {'paused': false});
  });

  test('令牌随请求发送，空令牌不带鉴权头', () async {
    final headers = <Map<String, String>>[];
    MockClient recorder() => MockClient((request) async {
      headers.add(request.headers);
      return http.Response(jsonEncode(apiEnvelope({})), 200);
    });

    final authorized = DesktopApiClient(
      config: const DesktopApiConfig(token: 'secret'),
      httpClient: recorder(),
    );
    await authorized.status();
    expect(headers.last['Authorization'], 'Bearer secret');
    expect(headers.last['X-API-Token'], 'secret');

    final anonymous = DesktopApiClient(httpClient: recorder());
    await anonymous.status();
    expect(headers.last.containsKey('Authorization'), isFalse);
  });

  test('解析 24 小时汇总，缺字段按零值', () async {
    final backend = FakeDesktopBackend();
    final summary = (await backend.client().queryStats()).summary;
    expect(summary.queries, 12345);
    expect(summary.blocked, 987);
    expect(summary.cached, 8000);
    expect(summary.forwarded, 3000);
    expect(summary.errors, 12);
    expect(summary.averageResponseMs, 12.4);
    expect(summary.cacheHitRate, closeTo(0.648, 0.0001));
    expect(summary.passed, 12345 - 987);

    final client = clientOf(
      MockClient((_) async => http.Response(jsonEncode(apiEnvelope({})), 200)),
    );
    final empty = (await client.queryStats()).summary;
    expect(empty.queries, 0);
    expect(empty.passed, 0);
    expect(empty.cacheHitRate, 0);
  });

  test('解析三列排行，缺列表按空处理', () async {
    final backend = FakeDesktopBackend(
      queryStats: queryStatsPayload(
        topDomains: const [
          {'name': 'api.example.com', 'count': 321},
        ],
        topClients: const [
          {'name': 'laptop', 'count': 45},
          {'name': 'phone'},
        ],
      ),
    );
    final stats = await backend.client().queryStats();
    expect(stats.topDomains.single.name, 'api.example.com');
    expect(stats.topDomains.single.count, 321);
    expect(stats.topBlocked, isEmpty);
    expect(stats.topClients.last.count, 0, reason: '缺 count 按零值解析');

    final client = clientOf(
      MockClient((_) async => http.Response(jsonEncode(apiEnvelope({})), 200)),
    );
    final empty = await client.queryStats();
    expect(empty.topDomains, isEmpty);
    expect(empty.topBlocked, isEmpty);
    expect(empty.topClients, isEmpty);
  });

  test('日志检索只把设了值的条件放进查询串', () async {
    final urls = <Uri>[];
    final client = clientOf(
      MockClient((request) async {
        urls.add(request.url);
        return http.Response(jsonEncode(apiEnvelope(queryLogPayload())), 200);
      }),
    );

    await client.searchQueries(offset: 50);
    expect(urls.last.queryParameters, {
      'limit': '25',
      'offset': '50',
      'includeFile': '1',
    });

    await client.searchQueries(
      domain: 'example.com',
      status: DesktopLogStatus.blocked,
    );
    expect(urls.last.queryParameters, {
      'limit': '25',
      'offset': '0',
      'includeFile': '1',
      'domain': 'example.com',
      'status': 'blocked',
    });

    await client.searchQueries(client: '192.168.1.20', qtype: 'AAAA');
    expect(urls.last.queryParameters, {
      'limit': '25',
      'offset': '0',
      'includeFile': '1',
      'client': '192.168.1.20',
      'qtype': 'AAAA',
    });
  });

  test('清空历史是一次 POST，失败透出服务端的错误', () async {
    final backend = FakeDesktopBackend();
    await backend.client().clearQueryLog();
    expect(backend.has('/api/v1/querylog/clear'), isTrue);

    final failing = clientOf(
      MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({'success': false, 'error': '日志文件不可写'}),
          ),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      failing.clearQueryLog(),
      throwsA(
        isA<DesktopApiException>().having(
          (error) => error.message,
          'message',
          '日志文件不可写',
        ),
      ),
    );
  });

  test('查询日志配置读得回、写得进，且不发送服务端拥有的目录', () async {
    final backend = FakeDesktopBackend();
    final config = await backend.client().queryLogConfig();
    expect(config.enabled, isTrue);
    expect(config.maxEntries, 10000);
    expect(config.fileEnabled, isTrue);
    expect(config.retentionDays, 7);
    expect(config.logClients, isTrue);
    expect(config.dataDir, isNotEmpty);

    await backend.client().updateQueryLogConfig(
      config.copyWith(maxEntries: 500, retentionDays: 3),
    );
    final update = backend.configUpdates.single;
    expect(update['maxEntries'], 500);
    expect(update['retentionDays'], 3);
    expect(update['enabled'], isTrue);
    expect(update.containsKey('dataDir'), isFalse);

    // 写后回读的是服务端状态，而不是页面自己拼的预期。
    final reread = await backend.client().queryLogConfig();
    expect(reread.retentionDays, 3);
    expect(reread.dataDir, config.dataDir);
  });

  test('缺字段的查询日志配置按零值解析', () async {
    final client = clientOf(
      MockClient((_) async => http.Response(jsonEncode(apiEnvelope({})), 200)),
    );
    final config = await client.queryLogConfig();
    expect(config.enabled, isFalse);
    expect(config.maxEntries, 0);
    expect(config.retentionDays, 0);
    expect(config.dataDir, isEmpty);
  });
}
