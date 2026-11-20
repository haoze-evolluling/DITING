part of 'rust_agent_core.dart';

enum AgentPasteKind { empty, json, both, baseUrl, key }

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

class AgentPaste {
  const AgentPaste({required this.kind, this.baseUrl, this.apiKey, this.model});

  final AgentPasteKind kind;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
}

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

  final String? unavailableReason;

  bool get isEmpty => dnsSamples == 0 && httpSamples == 0;

  String render() => RustAgentCore.instance.renderSummary(this);
}

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

enum AgentStatusKind {
  badKey,
  noAccess,
  modelNotFound,
  rateLimited,
  unavailable,
  requestFailed,
}
