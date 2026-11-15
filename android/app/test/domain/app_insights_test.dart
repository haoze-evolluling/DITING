import 'package:diting_android/data/native/flow_bridge.dart';
import 'package:diting_android/data/network/app_insights.dart';
import 'package:flutter_test/flutter_test.dart';

FlowRow _row({
  String app = 'com.example',
  String domain = 'example.com',
  int up = 0,
  int down = 0,
  String status = 'active',
  int seq = 0,
  String dstIp = '1.1.1.1',
}) => FlowRow(
  protocol: 'tcp',
  srcIp: '10.0.0.2',
  srcPort: 12345,
  dstIp: dstIp,
  dstPort: 443,
  uid: 1000,
  package: app,
  domain: domain,
  upBytes: up,
  downBytes: down,
  status: status,
  firstSeenMs: 0,
  lastSeenMs: 0,
  seq: seq,
);

void main() {
  group('buildAppReports', () {
    test('groups by app and sums traffic', () {
      final reports = buildAppReports([
        _row(app: 'a', domain: 'x', up: 10, down: 90),
        _row(app: 'a', domain: 'y', up: 5, down: 5),
        _row(app: 'b', domain: 'z', up: 1, down: 1),
      ]);
      expect(reports.length, 2);
      // "a" has more total bytes, so it comes first.
      expect(reports.first.appLabel, 'a');
      expect(reports.first.connectionCount, 2);
      expect(reports.first.totalBytes, 110);
    });

    test('counts blocks and exposes a ratio', () {
      final report = buildAppReports([
        _row(app: 'a', status: 'failed'),
        _row(app: 'a', status: 'active'),
        _row(app: 'a', status: 'failed'),
      ]).single;
      expect(report.blockedCount, 2);
      expect(report.blockedRatio, closeTo(2 / 3, 0.0001));
      expect(report.hasBlocked, isTrue);
    });

    test('keeps at most three top domains, busiest first', () {
      final report = buildAppReports([
        _row(domain: 'one', down: 1),
        _row(domain: 'two', down: 100),
        _row(domain: 'three', down: 50),
        _row(domain: 'four', down: 10),
      ]).single;
      expect(report.topDomains.length, 3);
      expect(report.topDomains.first.domain, 'two');
    });
  });

  group('buildConnectionMap', () {
    test('groups domains under each app, sorted by app', () {
      final map = buildConnectionMap([
        _row(app: 'beta', domain: 'b.example'),
        _row(app: 'alpha', domain: 'a.example'),
        _row(app: 'alpha', domain: 'c.example'),
      ]);
      expect(map.map((g) => g.appLabel).toList(), ['alpha', 'beta']);
      expect(map.first.domains.length, 2);
      expect(map.last.domains.single.domain, 'b.example');
    });

    test('falls back to dst ip when the domain is empty', () {
      final map = buildConnectionMap([
        _row(app: 'a', domain: '', dstIp: '9.9.9.9'),
      ]);
      expect(map.single.domains.single.domain, '9.9.9.9');
    });
  });
}
