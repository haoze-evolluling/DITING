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
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

part 'rust_agent_core_models.dart';
part 'rust_agent_core_payload.dart';

/// Must match `ABI_VERSION` in `rust/diting-agent-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DAG1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31474144;

/// Explicit library path, for a dev build or a test runner outside the app bundle.
const _pathVariable = 'DITING_AGENT_CORE_LIB';

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _EntryNative = Pointer<Uint8> Function(
  Pointer<Uint8>,
  Size,
  Pointer<Size>,
);
typedef _EntryDart = Pointer<Uint8> Function(
  Pointer<Uint8>,
  int,
  Pointer<Size>,
);
typedef _AllocNative = Pointer<Uint8> Function(Size);
typedef _AllocDart = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>, Size);
typedef _FreeDart = void Function(Pointer<Uint8>, int);

class RustAgentCore {
  RustAgentCore._(
    this._paste,
    this._secret,
    this._prompt,
    this._summary,
    this._api,
    this._alloc,
    this._free,
    this.libraryPath,
  );

  final _EntryDart _paste;
  final _EntryDart _secret;
  final _EntryDart _prompt;
  final _EntryDart _summary;
  final _EntryDart _api;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  static RustAgentCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustAgentCore get instance => _instance ??= _load();

  static RustAgentCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_agent_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustAgentCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_agent_core_paste',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_agent_core_secret',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_agent_core_prompt',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_agent_core_summary',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_agent_core_api',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_agent_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_agent_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'agent core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    // Cargo turns `diting-agent-core` into `libditing_agent_core.so` / `.dylib` and
    // `diting_agent_core.dll`.
    if (Platform.isAndroid) {
      // 方案 B: all sixteen UI-side kernels share one Android library.
      return 'libditing_kernels.so';
    }
    if (Platform.isLinux) {
      return 'libditing_agent_core.so';
    }
    if (Platform.isWindows) return 'diting_agent_core.dll';
    if (Platform.isMacOS) return 'libditing_agent_core.dylib';
    return null;
  }

  /// Probe order: explicit path, the packaged library name, then repo build output — the last one
  /// lets `flutter test` on the desktop host exercise the real native path without an APK.
  static Iterable<String> _libraryCandidates() sync* {
    final explicit = Platform.environment[_pathVariable];
    if (explicit != null && explicit.isNotEmpty) {
      yield explicit;
    }
    final libraryName = _libraryName();
    if (libraryName == null) {
      return;
    }
    yield libraryName;
    var directory = Directory.current;
    for (var depth = 0; depth < 6; depth++) {
      for (final profile in const ['release', 'debug']) {
        yield '${directory.path}/rust/target/$profile/$libraryName';
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        return;
      }
      directory = parent;
    }
  }

  /// Clipboard recognition: JSON → URL + key → bare URL → bare key.
  AgentPaste parsePaste(String raw) {
    // The paste entry takes the raw text, without a length prefix: it is not a payload.
    final reader = _call(_paste, _PayloadWriter()..rawUtf8(raw));
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
      _secret,
      _PayloadWriter()
        ..u8(0)
        ..utf8(plain),
    );
    return reader.string();
  }

  /// Restores a sealed key; undecodable input yields `''` rather than throwing.
  String openKey(String sealed) {
    final reader = _call(
      _secret,
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
    final reader = _call(_prompt, writer);
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
    final reader = _call(_prompt, writer);
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
    final reader = _call(_summary, writer);
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
    return _call(_summary, writer).string();
  }

  /// `/chat/completions` for a base URL. Throws [AgentKernelException] when it is blank.
  String chatEndpoint(String baseUrl) {
    final reader = _call(
      _api,
      _PayloadWriter()
        ..u8(0)
        ..utf8(baseUrl),
    );
    return _endpointOf(reader);
  }

  /// `/models` for a base URL. Throws [AgentKernelException] when it is blank.
  String modelsEndpoint(String baseUrl) {
    final reader = _call(
      _api,
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
    return _call(_api, writer).string();
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
      _api,
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
      _api,
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
      _api,
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
    // Rust `ParseError` discriminants 1..6 line up with these names.
    const failures = [
      AgentKernelFailure.invalidJson,
      AgentKernelFailure.notJsonObject,
      AgentKernelFailure.emptyContent,
      AgentKernelFailure.noModelListJson,
      AgentKernelFailure.noModelListData,
      AgentKernelFailure.noModels,
    ];
    final index = kind - 1;
    return index >= 0 && index < failures.length
        ? failures[index]
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

  /// Copies `payload` in, calls `entry`, copies the answer out and releases both buffers.
  _PayloadReader _call(_EntryDart entry, _PayloadWriter writer) {
    final bytes = writer.finish();
    final inputPtr = bytes.isEmpty ? nullptr : _alloc(bytes.length);
    final outLenPtr = _alloc(sizeOf<Size>()).cast<Size>();
    Pointer<Uint8> outputPtr = nullptr;
    var outputLength = 0;
    try {
      if (bytes.isNotEmpty) {
        inputPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      outputPtr = entry(inputPtr, bytes.length, outLenPtr);
      outputLength = outLenPtr.value;
      if (outputPtr == nullptr || outputLength == 0) {
        throw StateError('agent core rejected the payload');
      }
      final reader = _PayloadReader(
        Uint8List.fromList(outputPtr.asTypedList(outputLength)),
      );
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
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, bytes.length);
      _free(outLenPtr.cast<Uint8>(), sizeOf<Size>());
      if (outputPtr != nullptr && outputLength > 0) {
        _free(outputPtr, outputLength);
      }
    }
  }
}
