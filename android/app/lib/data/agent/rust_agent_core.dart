/// The native AI-analysis core: the Rust crate in `rust/diting-agent-core`, loaded over `dart:ffi`.
///
/// The library is required. [`RustAgentCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first call instead of quietly running a second copy
/// of the paste recogniser, the key masks or the prompt text.
///
/// Payload layout lives in `rust/diting-agent-core/src/ffi.rs`; `_abiVersion` must match
/// `ABI_VERSION` there, and the Rust tests fail on a payload change precisely so this number moves
/// with it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diting_android/data/db/kernel_core.dart';

part 'rust_agent_core_models.dart';
part 'rust_agent_core_payload.dart';

/// Must match `ABI_VERSION` in `rust/diting-agent-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DAG1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31474144;

class RustAgentCore {
  RustAgentCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustAgentCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustAgentCore get instance => _instance ??= _load();

  static RustAgentCore _load() => RustAgentCore._(
    KernelCore.load(
      crate: 'diting-agent-core',
      payloadMagic: _payloadMagic,
      abiVersion: _abiVersion,
      errorPrefix: 'agent core',
      entries: const ['paste', 'secret', 'prompt', 'summary', 'api'],
    ),
  );

  /// Clipboard recognition: JSON → URL + key → bare URL → bare key.
  AgentPaste parsePaste(String raw) {
    // The paste entry takes the raw text, without a length prefix: it is not a payload.
    final reader = _call('paste', _PayloadWriter()..rawUtf8(raw));
    final kindIndex = reader.u8();
    final kind = kindIndex < AgentPasteKind.values.length
        ? AgentPasteKind.values[kindIndex]
        : AgentPasteKind.empty;
    return AgentPaste(
      kind: kind,
      baseUrl: reader.optionalString(),
      apiKey: reader.optionalString(),
      model: reader.optionalString(),
    );
  }

  /// Seals a plaintext key with the legacy XOR masks; blank input stays blank.
  String sealKey(String plain) {
    final reader = _call(
      'secret',
      _PayloadWriter()
        ..u8(0)
        ..utf8(plain),
    );
    return reader.string();
  }

  /// Restores a sealed key; undecodable input yields `''` rather than throwing.
  String openKey(String sealed) {
    final reader = _call(
      'secret',
      _PayloadWriter()
        ..u8(1)
        ..utf8(sealed),
    );
    return reader.string();
  }

  /// The domain-analysis prompt with its four sections.
  ({String systemPrompt, String userPrompt}) domainPrompt({
    required String domain,
    required String systemPrompt,
    String? context,
  }) {
    final writer = _PayloadWriter()
      ..u8(0)
      ..utf8(domain)
      ..utf8(systemPrompt)
      ..optionalUtf8(context);
    final reader = _call('prompt', writer);
    return (systemPrompt: reader.string(), userPrompt: reader.string());
  }

  /// The traffic-analysis prompt, wrapping the rendered summary.
  ({String systemPrompt, String userPrompt}) trafficPrompt({
    required RecentTrafficSummary summary,
    required String systemPrompt,
  }) {
    final writer = _PayloadWriter()
      ..u8(1)
      ..utf8(systemPrompt);
    _writeSummary(writer, summary);
    final reader = _call('prompt', writer);
    return (systemPrompt: reader.string(), userPrompt: reader.string());
  }

  /// Aggregates the two log tables into the numbers the prompt shows the model.
  RecentTrafficSummary summarize({
    required List<AgentDnsRow> dnsRows,
    required List<String> httpOutcomes,
    String? unavailableReason,
  }) {
    final writer = _PayloadWriter()
      ..u8(0)
      ..optionalUtf8(unavailableReason)
      ..u32(dnsRows.length);
    for (final row in dnsRows) {
      writer
        ..utf8(row.domain)
        ..utf8(row.result)
        ..u8(row.cached ? 1 : 0);
    }
    writer.u32(httpOutcomes.length);
    for (final outcome in httpOutcomes) {
      writer.utf8(outcome);
    }
    final reader = _call('summary', writer);
    final dnsSamples = reader.u32();
    final blockedDns = reader.u32();
    final rewrittenDns = reader.u32();
    final cachedDns = reader.u32();
    final httpSamples = reader.u32();
    final blockedHttp = reader.u32();
    final bypassedHttp = reader.u32();
    final unavailable = reader.optionalString();
    return RecentTrafficSummary(
      dnsSamples: dnsSamples,
      blockedDns: blockedDns,
      rewrittenDns: rewrittenDns,
      cachedDns: cachedDns,
      topDomains: reader.domainCounts(),
      httpSamples: httpSamples,
      blockedHttp: blockedHttp,
      bypassedHttp: bypassedHttp,
      unavailableReason: unavailable,
    );
  }

  /// The model-facing section for an already aggregated summary.
  String renderSummary(RecentTrafficSummary summary) {
    final writer = _PayloadWriter()..u8(1);
    _writeSummary(writer, summary);
    return _call('summary', writer).string();
  }

  /// `/chat/completions` for a base URL. Throws [AgentKernelException] when it is blank.
  String chatEndpoint(String baseUrl) {
    final reader = _call(
      'api',
      _PayloadWriter()
        ..u8(0)
        ..utf8(baseUrl),
    );
    return _endpointOf(reader);
  }

  /// `/models` for a base URL. Throws [AgentKernelException] when it is blank.
  String modelsEndpoint(String baseUrl) {
    final reader = _call(
      'api',
      _PayloadWriter()
        ..u8(1)
        ..utf8(baseUrl),
    );
    return _endpointOf(reader);
  }

  /// The JSON body of a chat completion request.
  String chatBody({
    required String model,
    required List<({String role, String content})> messages,
    required double temperature,
  }) {
    final writer = _PayloadWriter()
      ..u8(2)
      ..utf8(model)
      ..f64(temperature)
      ..u32(messages.length);
    for (final message in messages) {
      writer
        ..utf8(message.role)
        ..utf8(message.content);
    }
    return _call('api', writer).string();
  }

  /// Reads content, model and usage out of a completion response.
  ({
    String content,
    String model,
    int promptTokens,
    int completionTokens,
    int totalTokens,
  })
  parseChat(String body, {required String fallbackModel}) {
    final reader = _call(
      'api',
      _PayloadWriter()
        ..u8(3)
        ..utf8(body)
        ..utf8(fallbackModel),
    );
    final kind = reader.u8();
    if (kind != 0) throw AgentKernelException(_failureOf(kind));
    final content = reader.string();
    final model = reader.string();
    return (
      content: content,
      model: model,
      promptTokens: reader.u32(),
      completionTokens: reader.u32(),
      totalTokens: reader.u32(),
    );
  }

  /// Model ids from `data` / `models` / `result`, trimmed, de-duplicated and sorted.
  List<String> parseModels(String body) {
    final reader = _call(
      'api',
      _PayloadWriter()
        ..u8(4)
        ..utf8(body),
    );
    final kind = reader.u8();
    if (kind != 0) throw AgentKernelException(_failureOf(kind));
    final count = reader.u32();
    return List<String>.generate(count, (_) => reader.string());
  }

  /// Status hint plus the server's own sentence (truncated to 200 UTF-16 units).
  ({AgentStatusKind kind, String? detail}) describeStatus(
    int status,
    String body,
  ) {
    final reader = _call(
      'api',
      _PayloadWriter()
        ..u8(5)
        ..u32(status)
        ..utf8(body),
    );
    final kindIndex = reader.u8();
    final kind = kindIndex < AgentStatusKind.values.length
        ? AgentStatusKind.values[kindIndex]
        : AgentStatusKind.requestFailed;
    return (kind: kind, detail: reader.optionalString());
  }

  String _endpointOf(_PayloadReader reader) {
    final ok = reader.u8();
    if (ok != 1) {
      throw const AgentKernelException(AgentKernelFailure.emptyEndpoint);
    }
    return reader.string();
  }

  AgentKernelFailure _failureOf(int kind) {
    // Rust `ParseError` discriminants 1..6 are the declaration order shifted by one
    // (`emptyEndpoint` occupies 0), so the kind indexes the enum directly.
    return kind > 0 && kind < AgentKernelFailure.values.length
        ? AgentKernelFailure.values[kind]
        : AgentKernelFailure.invalidJson;
  }

  static void _writeSummary(
    _PayloadWriter writer,
    RecentTrafficSummary summary,
  ) {
    writer
      ..u32(summary.dnsSamples)
      ..u32(summary.blockedDns)
      ..u32(summary.rewrittenDns)
      ..u32(summary.cachedDns)
      ..u32(summary.httpSamples)
      ..u32(summary.blockedHttp)
      ..u32(summary.bypassedHttp)
      ..optionalUtf8(summary.unavailableReason)
      ..u32(summary.topDomains.length);
    for (final entry in summary.topDomains) {
      writer
        ..utf8(entry.domain)
        ..u32(entry.count);
    }
  }

  /// Sends one payload to [entry] and checks the reply header.
  _PayloadReader _call(String entry, _PayloadWriter writer) {
    final reply = _core.invoke(writer.finish(), entry: entry);
    if (reply.isEmpty) {
      throw StateError('agent core rejected the payload');
    }
    final reader = _PayloadReader(reply);
    if (reader.u32() != _payloadMagic) {
      throw const FormatException('agent core payload magic mismatch');
    }
    final abiVersion = reader.u32();
    if (abiVersion != _abiVersion) {
      throw FormatException(
        'agent core payload abi $abiVersion, expected $_abiVersion',
      );
    }
    return reader;
  }
}
