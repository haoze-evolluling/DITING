library;

import 'package:diting_android/data/agent/rust_agent_core.dart';
import 'package:diting_android/app/l10n/l10n.dart';

class AgentApiTextParseResult {
  const AgentApiTextParseResult({
    this.baseUrl,
    this.apiKey,
    this.model,
    required this.message,
  });

  final String? baseUrl;
  final String? apiKey;
  final String? model;

  final String message;

  bool get isEmpty => baseUrl == null && apiKey == null && model == null;
}

AgentApiTextParseResult parseAgentApiText(String raw) {
  final parsed = RustAgentCore.instance.parsePaste(raw);
  return AgentApiTextParseResult(
    baseUrl: parsed.baseUrl,
    apiKey: parsed.apiKey,
    model: parsed.model,
    message: switch (parsed.kind) {
      AgentPasteKind.json => currentL10n.agentPasteJson,
      AgentPasteKind.both => currentL10n.agentPasteBoth,
      AgentPasteKind.baseUrl => currentL10n.agentPasteBaseUrl,
      AgentPasteKind.key => currentL10n.agentPasteKey,
      AgentPasteKind.empty => currentL10n.agentPasteEmpty,
    },
  );
}
