// The push channel is what makes the live list live, so its wire format is pinned here: which
// event types become queries, how a query is classified, and where the socket points. A payload
// this build cannot read has to disappear rather than become a blank row.

import 'dart:convert';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_event_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String wire(Object? data, {String type = 'query', int timestamp = 1700000000123}) =>
      jsonEncode({'type': type, 'timestamp': timestamp, 'data': data});

  Map<String, Object?> queryData({
    String domain = 'example.com.',
    String qtype = 'A',
    String clientIp = '192.168.1.20',
    String clientName = '',
    double durationMs = 4.5,
    bool success = true,
    String rcode = 'NOERROR',
    String cacheHit = '',
    bool blocked = false,
    String filterRule = '',
    String filterReason = '',
    String errorMessage = '',
  }) => {
    'domain': domain,
    'qtype': qtype,
    'clientIP': clientIp,
    'clientName': clientName,
    'durationMs': durationMs,
    'success': success,
    'rcode': rcode,
    'cacheHit': cacheHit,
    'blocked': blocked,
    'filterRule': filterRule,
    'filterReason': filterReason,
    'errorMessage': errorMessage,
  };

  test('query 事件按字段与连接时间戳解析', () {
    final query = desktopQueryFromEvent(
      wire(queryData(clientName: 'laptop'), timestamp: 1700000000123),
    )!;

    expect(query.domain, 'example.com.');
    expect(query.displayDomain, 'example.com');
    expect(query.client, 'laptop');
    expect(query.clientIp, '192.168.1.20');
    expect(query.durationMs, 4.5);
    expect(query.status, DesktopLiveStatus.passed);
    expect(
      query.timestamp,
      DateTime.fromMillisecondsSinceEpoch(1700000000123),
    );
  });

  test('分类顺序是失败、拦截、缓存、回源', () {
    DesktopLiveStatus statusOf(Map<String, Object?> data) =>
        desktopQueryFromEvent(wire(data))!.status;

    expect(statusOf(queryData(blocked: true)), DesktopLiveStatus.blocked);
    expect(
      statusOf(queryData(cacheHit: 'hit')),
      DesktopLiveStatus.cached,
      reason: '命中缓存',
    );
    expect(
      statusOf(queryData(cacheHit: 'stale')),
      DesktopLiveStatus.stale,
      reason: '容灾复用',
    );
    expect(
      statusOf(queryData(success: false)),
      DesktopLiveStatus.error,
      reason: '失败优先于拦截标记',
    );
    expect(
      statusOf(queryData(blocked: true, errorMessage: 'upstream timeout')),
      DesktopLiveStatus.error,
    );
  });

  test('响应码缺省时按 success 推回三个可筛的词', () {
    String codeOf(Map<String, Object?> data) =>
        desktopQueryFromEvent(wire(data))!.responseCode;

    expect(codeOf(queryData(rcode: 'NXDOMAIN')), 'NXDOMAIN');
    expect(codeOf(queryData(rcode: '')), 'NOERROR');
    expect(codeOf(queryData(rcode: '', success: false)), 'SERVFAIL');
  });

  test('拦截原因优先取 filterReason，其次 filterRule', () {
    expect(
      desktopQueryFromEvent(
        wire(queryData(blocked: true, filterRule: '||ads^', filterReason: '广告')),
      )!.blockReason,
      '广告',
    );
    expect(
      desktopQueryFromEvent(
        wire(queryData(blocked: true, filterRule: '||ads^')),
      )!.blockReason,
      '||ads^',
    );
  });

  test('非 query 事件、坏载荷与缺字段都不会变成一条空查询', () {
    expect(desktopQueryFromEvent(wire('started', type: 'dns')), isNull);
    expect(desktopQueryFromEvent('not json'), isNull);
    expect(desktopQueryFromEvent('[1,2]'), isNull);
    expect(desktopQueryFromEvent(wire('a string')), isNull);
    expect(desktopQueryFromEvent(const <int>[1, 2, 3]), isNull);

    final sparse = desktopQueryFromEvent(wire(const <String, Object?>{}))!;
    expect(sparse.domain, isEmpty);
    expect(sparse.durationMs, 0);
    expect(sparse.status, DesktopLiveStatus.error, reason: '缺 success 即未知');
  });

  test('套接字地址带令牌，空令牌不带参数', () {
    final withToken = DesktopEventClient(
      config: const DesktopApiConfig(port: 15353, token: 'secret'),
    );
    expect(withToken.uri.scheme, 'ws');
    expect(withToken.uri.host, '127.0.0.1');
    expect(withToken.uri.port, 15353);
    expect(withToken.uri.path, '/api/v1/events');
    expect(withToken.uri.queryParameters['token'], 'secret');

    final anonymous = DesktopEventClient(config: const DesktopApiConfig());
    expect(anonymous.uri.hasQuery, isFalse);
  });
}
