/// Smart parsing of pasted API configuration: a JSON blob, a "base URL + key" pair, a bare URL, or a
/// bare key.
///
/// The recogniser is the native kernel (`rust/diting-agent-core/src/paste.rs`), which keeps the 1.4.x
/// token order so both apps accept the same paste shapes. Only the sentence is localised here.
library;

import 'package:diting_android/data/agent/rust_agent_core.dart';
import 'package:diting_shared/app/l10n/l10n.dart';

/// One parse attempt. Empty fields mean "leave what the user typed alone".
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

  /// What to tell the user, e.g. 已自动识别并填入服务地址与 API Key.
  final String message;

  bool get isEmpty => baseUrl == null && apiKey == null && model == null;
}

/// Four-step recognition: JSON → URL+key pair → bare URL → bare key.
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
