library;

import 'package:diting_android/data/agent/rust_agent_core.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';

export 'package:diting_android/data/agent/rust_agent_core.dart'
    show RecentTrafficSummary;

Future<RecentTrafficSummary> summarizeRecentTraffic({
  required DnsLogRepository dnsRepository,
  HttpRequestRepository? httpRepository,
  int dnsLimit = 40,
  int httpLimit = 30,
  String? httpUnavailableReason,
}) async {
  final dnsRows = await dnsRepository.recent(limit: dnsLimit);
  var httpOutcomes = const <String>[];
  var unavailable = httpUnavailableReason;
  if (httpRepository != null && unavailable == null) {
    try {
      final rows = await httpRepository.recent(limit: httpLimit);
      httpOutcomes = [for (final row in rows) row.outcome];
    } on Object catch (error) {
      unavailable = '$error';
    }
  }
  return RustAgentCore.instance.summarize(
    dnsRows: [
      for (final row in dnsRows)
        AgentDnsRow(domain: row.domain, result: row.result, cached: row.cached),
    ],
    httpOutcomes: httpOutcomes,
    unavailableReason: unavailable,
  );
}
