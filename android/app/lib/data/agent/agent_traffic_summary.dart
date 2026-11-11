/// Aggregates the two real log tables into the numbers the traffic prompt shows the model.
///
/// The reads are here (sqflite); the counting, the top-domain ordering and the rendered section are
/// in `rust/diting-agent-core/src/traffic.rs`, because the prompt says exactly what each counter
/// means and a second implementation is how those two drift.
library;

import 'package:diting_android/data/agent/rust_agent_core.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';

export 'package:diting_android/data/agent/rust_agent_core.dart'
    show RecentTrafficSummary;

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
  var httpOutcomes = const <String>[];
  var unavailable = httpUnavailableReason;
  if (httpRepository != null && unavailable == null) {
    try {
      final rows = await httpRepository.recent(limit: httpLimit);
      httpOutcomes = [for (final row in rows) row.outcome];
    } on Object catch (error) {
      // The express DB lacks this table and throws `no such table`: the surface does not exist, not
      // that there was no traffic.
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
