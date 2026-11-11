part of 'rust_agent_core.dart';

/// Which of the four paste shapes matched; the caller maps it to a localised sentence.
///
/// Declaration order is the wire order: `paste::PasteKind` in
/// `rust/diting-agent-core/src/paste.rs` uses these indices as discriminants.
enum AgentPasteKind { empty, json, both, baseUrl, key }

/// The kernel reported a semantic rejection; the caller turns it into a localised message.
///
/// Declaration order is the wire order shifted by one: `api::ParseError` writes `1..=6`.
enum AgentKernelFailure {
  emptyEndpoint,
  invalidJson,
  notJsonObject,
  emptyContent,
  noModelListJson,
  noModelListData,
  noModels,
}

class AgentKernelException implements Exception {
  const AgentKernelException(this.failure);

  final AgentKernelFailure failure;

  @override
  String toString() => 'agent kernel: ${failure.name}';
}

/// What the four-step clipboard recogniser found. Null fields mean "leave what the user typed".
class AgentPaste {
  const AgentPaste({required this.kind, this.baseUrl, this.apiKey, this.model});

  final AgentPasteKind kind;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
}

/// The numbers behind the traffic prompt, as the kernel aggregated them.
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

  /// The section the model sees; one implementation, in `traffic.rs`.
  String render() => RustAgentCore.instance.renderSummary(this);
}

/// One `dns_log` row reduced to the three fields the aggregation reads.
class AgentDnsRow {
  const AgentDnsRow({
    required this.domain,
    required this.result,
    required this.cached,
  });

  final String domain;
  final String result;
  final bool cached;
}

/// How an HTTP status is reported to the user, once the Dart side has localised it.
///
/// Declaration order matches `api::StatusKind` in `rust/diting-agent-core/src/api.rs`.
enum AgentStatusKind {
  badKey,
  noAccess,
  modelNotFound,
  rateLimited,
  unavailable,
  requestFailed,
}
