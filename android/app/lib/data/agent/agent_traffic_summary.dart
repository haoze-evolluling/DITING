/// Aggregates the two real log tables into the numbers the traffic prompt shows the model.
library;

import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';

class RecentTrafficSummary {
  const RecentTrafficSummary({
    required this.dnsSamples,
    required this.blockedDns,
    required this.rewrittenDns,
    required this.cachedDns,
    required this.topDomains,
    required this.httpSamples,
    required this.blockedHttp,
    required this.bypassedHttp,
    this.unavailableReason,
  });

  final int dnsSamples;
  final int blockedDns;
  final int rewrittenDns;
  final int cachedDns;

  final List<({String domain, int count})> topDomains;

  final int httpSamples;
  final int blockedHttp;
  final int bypassedHttp;

  /// Why the tables are unavailable (the express DB has no `http_request_log`).
  final String? unavailableReason;

  bool get isEmpty => dnsSamples == 0 && httpSamples == 0;

  /// Text for the model. Empty data says "no records" instead of omitting the section, which would
  /// read as "nothing mentioned means nothing wrong".
  String render() {
    final buffer = StringBuffer()
      ..writeln('【近期 DNS 监控统计】')
      ..writeln('- 采样数量: $dnsSamples 条')
      ..writeln(
        '- 规则拦截: $blockedDns 条, 规则覆写: $rewrittenDns 条, '
        '缓存命中: $cachedDns 条',
      );
    if (topDomains.isEmpty) {
      buffer.writeln('- 高频请求域名: 采样窗口内没有任何 DNS 记录');
    } else {
      buffer.writeln('- 高频请求域名:');
      for (final entry in topDomains) {
        buffer.writeln('  * ${entry.domain} (请求 ${entry.count} 次)');
      }
    }
    buffer
      ..writeln()
      ..writeln('【近期 HTTP/HTTPS 流量统计】');
    if (unavailableReason != null) {
      buffer.writeln('- 本工作模式没有 HTTPS 检查面：$unavailableReason');
    } else if (httpSamples == 0) {
      buffer.writeln('- 采样数量: 0 条（未装/未信任 CA 时不产生此类记录）');
    } else {
      buffer.writeln(
        '- 采样数量: $httpSamples 条, 拦截数: $blockedHttp, '
        '旁路直连数: $bypassedHttp',
      );
    }
    return buffer.toString().trimRight();
  }
}

/// Aggregates both real log tables. A null [httpRepository] means this mode has no HTTPS surface,
/// which is not a failure.
Future<RecentTrafficSummary> summarizeRecentTraffic({
  required DnsLogRepository dnsRepository,
  HttpRequestRepository? httpRepository,
  int dnsLimit = 40,
  int httpLimit = 30,
  String? httpUnavailableReason,
}) async {
  final dnsRows = await dnsRepository.recent(limit: dnsLimit);
  final counts = <String, int>{};
  var blocked = 0;
  var rewritten = 0;
  var cached = 0;
  for (final row in dnsRows) {
    counts[row.domain] = (counts[row.domain] ?? 0) + 1;
    final result = row.result.toUpperCase();
    if (result == 'BLOCKED') blocked++;
    if (result == 'REWRITTEN') rewritten++;
    if (row.cached) cached++;
  }
  final top = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });

  var httpSamples = 0;
  var blockedHttp = 0;
  var bypassedHttp = 0;
  var unavailable = httpUnavailableReason;
  if (httpRepository != null && unavailable == null) {
    try {
      final rows = await httpRepository.recent(limit: httpLimit);
      httpSamples = rows.length;
      for (final row in rows) {
        final outcome = row.outcome.toLowerCase();
        if (outcome == 'blocked') blockedHttp++;
        if (outcome == 'passthrough' || outcome == 'bypassed') bypassedHttp++;
      }
    } on Object catch (error) {
      // The express DB lacks this table and throws `no such table`: the surface does not exist, not
      // that there was no traffic.
      unavailable = '$error';
    }
  }

  return RecentTrafficSummary(
    dnsSamples: dnsRows.length,
    blockedDns: blocked,
    rewrittenDns: rewritten,
    cachedDns: cached,
    topDomains: [
      for (final entry in top.take(8)) (domain: entry.key, count: entry.value),
    ],
    httpSamples: httpSamples,
    blockedHttp: blockedHttp,
    bypassedHttp: bypassedHttp,
    unavailableReason: unavailable,
  );
}
