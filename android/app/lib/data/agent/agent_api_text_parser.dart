/// Smart parsing of pasted API configuration: a JSON blob, a "base URL + key" pair, a bare URL, or a
/// bare key. Ported verbatim from the 1.4.x Kotlin `AgentApiTextParser` so both apps accept the same
/// paste shapes; returns data instead of applying it so it stays testable without a widget.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:convert';

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

const _urlPattern = r'''https?://[^\s,;"'\(\)]+''';

final _urlRegex = RegExp(_urlPattern);

// Order matters: `sk-` keys first, then any long token, optionally behind "Bearer ".
final _keyRegex = RegExp(
  r'(?:sk-[a-zA-Z0-9_\-]{16,}|(?:Bearer\s+)?([a-zA-Z0-9_\-]{32,}))',
);

/// Strips the characters that a single-line field or a soft keyboard leaves behind.
String sanitizeAgentApiInput(String input) => input
    .replaceAll('\r', '')
    .replaceAll('\n', '')
    .replaceAll('\t', '')
    .replaceAll(' ', '')
    .trim();

/// Extracts a URL and a key from text that carries both, e.g. `https://api.x.com/v1, sk-abc…`.
({String baseUrl, String apiKey})? parseCompositeUrlAndKey(String input) {
  if (!input.contains('http://') && !input.contains('https://')) return null;
  final urlMatch = _urlRegex.firstMatch(input);
  if (urlMatch == null) return null;
  final extractedUrl = urlMatch[0]!.replaceFirst(RegExp(r'/+$'), '');
  final remaining = _stripNoise(
    input.replaceFirst(urlMatch[0]!, '').replaceFirst('Bearer ', ''),
  );
  if (remaining.isEmpty) return null;
  return (baseUrl: extractedUrl, apiKey: remaining);
}

String _stripNoise(String input) => input
    .replaceAll('\r', '')
    .replaceAll('\n', '')
    .replaceAll('\t', '')
    .replaceAll(' ', '')
    .replaceAll(RegExp(r'^[,;:\s]+'), '')
    .replaceAll(RegExp(r'[,;:\s]+$'), '');

/// Four-step recognition, in the same order as the Kotlin version:
/// JSON → URL+key pair → bare URL → bare key.
AgentApiTextParseResult parseAgentApiText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return AgentApiTextParseResult(message: currentL10n.agentPasteEmpty);
  }

  // 1. A JSON config, the shape every provider's docs paste.
  if (text.startsWith('{') && text.endsWith('}')) {
    final fromJson = _parseJsonConfig(text);
    if (fromJson != null) return fromJson;
  }

  // 2. Both a URL and a key somewhere in the paste.
  final foundUrl = _urlRegex
      .firstMatch(text)?[0]
      ?.replaceFirst(RegExp(r'/+$'), '');
  final textWithoutUrl = foundUrl == null
      ? text
      : text.replaceFirst(foundUrl, '');
  final foundKey = _keyRegex
      .firstMatch(textWithoutUrl)?[0]
      ?.replaceFirst('Bearer ', '')
      .trim();

  if (foundUrl != null && foundKey != null && foundKey.isNotEmpty) {
    return AgentApiTextParseResult(
      baseUrl: sanitizeAgentApiInput(foundUrl),
      apiKey: sanitizeAgentApiInput(foundKey),
      message: currentL10n.agentPasteBoth,
    );
  }

  // 3. Only a server address. Two lines is the cap: a longer paste without `sk-` is more likely a
  // key that happens to contain a URL, so it falls through to step 4.
  if (foundUrl != null &&
      text.split('\n').length <= 2 &&
      !text.contains('sk-')) {
    return AgentApiTextParseResult(
      baseUrl: sanitizeAgentApiInput(foundUrl),
      message: currentL10n.agentPasteBaseUrl,
    );
  }

  // 4. Treat the whole thing as a key, joining lines the field would have cut off.
  return AgentApiTextParseResult(
    apiKey: sanitizeAgentApiInput(text.replaceFirst('Bearer ', '')),
    message: currentL10n.agentPasteKey,
  );
}

AgentApiTextParseResult? _parseJsonConfig(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final map = Map<Object?, Object?>.from(decoded);
  String read(List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return '';
  }

  final key = read(const ['apiKey', 'api_key', 'key']);
  final url = read(const ['baseUrl', 'base_url', 'url']);
  final model = read(const ['model']);
  if (key.isEmpty && url.isEmpty && model.isEmpty) return null;
  return AgentApiTextParseResult(
    apiKey: key.isEmpty ? null : sanitizeAgentApiInput(key),
    baseUrl: url.isEmpty ? null : sanitizeAgentApiInput(url),
    model: model.isEmpty ? null : sanitizeAgentApiInput(model),
    message: currentL10n.agentPasteJson,
  );
}
