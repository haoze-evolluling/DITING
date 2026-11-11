/// Prompt text for the two analysis modes.
///
/// The four-section structure and the badge words (【高危】/【建议加入白名单】…) are what the Markdown
/// viewer colours, so the text is part of the rendered report's contract. It lives in
/// `rust/diting-agent-core/src/prompt.rs`: both prompts are addressed to the model, so neither is
/// localised.
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

/// Builds a domain analysis request with the four prompt sections users expect.
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
