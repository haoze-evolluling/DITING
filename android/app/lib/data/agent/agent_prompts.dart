library;

import 'package:diting_android/data/agent/rust_agent_core.dart';

class AgentAnalysisRequest {
  const AgentAnalysisRequest({
    required this.systemPrompt,
    required this.userPrompt,
  });

  final String systemPrompt;
  final String userPrompt;
}

AgentAnalysisRequest buildDomainAnalysisRequest({
  required String domain,
  required String systemPrompt,
  String? context,
}) {
  final built = RustAgentCore.instance.domainPrompt(
    domain: domain,
    systemPrompt: systemPrompt,
    context: context,
  );
  return AgentAnalysisRequest(
    systemPrompt: built.systemPrompt,
    userPrompt: built.userPrompt,
  );
}

AgentAnalysisRequest buildTrafficAnalysisRequest({
  required RecentTrafficSummary summary,
  required String systemPrompt,
}) {
  final built = RustAgentCore.instance.trafficPrompt(
    summary: summary,
    systemPrompt: systemPrompt,
  );
  return AgentAnalysisRequest(
    systemPrompt: built.systemPrompt,
    userPrompt: built.userPrompt,
  );
}
