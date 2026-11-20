library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diting_android/data/db/kernel_core.dart';

part 'rust_agent_core_models.dart';
part 'rust_agent_core_payload.dart';

const _abiVersion = 1;

const _payloadMagic = 0x31474144;

class RustAgentCore {
  RustAgentCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustAgentCore? _instance;

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

  AgentPaste parsePaste(String raw) {
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

  String sealKey(String plain) {
    final reader = _call(
      'secret',
      _PayloadWriter()
        ..u8(0)
        ..utf8(plain),
    );
    return reader.string();
  }

  String openKey(String sealed) {
    final reader = _call(
      'secret',
      _PayloadWriter()
        ..u8(1)
        ..utf8(sealed),
    );
    return reader.string();
  }

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

  String renderSummary(RecentTrafficSummary summary) {
    final writer = _PayloadWriter()..u8(1);
    _writeSummary(writer, summary);
    return _call('summary', writer).string();
  }

  String chatEndpoint(String baseUrl) {
    final reader = _call(
      'api',
      _PayloadWriter()
        ..u8(0)
        ..utf8(baseUrl),
    );
    return _endpointOf(reader);
  }

  String modelsEndpoint(String baseUrl) {
    final reader = _call(
      'api',
      _PayloadWriter()
        ..u8(1)
        ..utf8(baseUrl),
    );
    return _endpointOf(reader);
  }

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
