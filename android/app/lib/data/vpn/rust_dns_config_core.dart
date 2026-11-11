/// The native DNS configuration core: the Rust crate in `rust/diting-dns-config-core`, loaded over
/// `dart:ffi`.
///
/// The library is required. [`RustDnsConfigCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first config push instead of quietly pushing a
/// second, drifting document.
///
/// Payload layout lives in `rust/diting-dns-config-core/src/ffi.rs`; `_abiVersion` must match
/// `ABI_VERSION` there.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

part 'rust_dns_config_core_payload.dart';
part 'rust_dns_config_core_records.dart';

/// Must match `ABI_VERSION` in `rust/diting-dns-config-core/src/ffi.rs`.
const _abiVersion = 2;

/// `"DDC1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31434444;

/// Explicit library path, for a dev build or a test runner outside the app bundle.
const _pathVariable = 'DITING_DNS_CONFIG_CORE_LIB';

// Operation bytes, mirroring the Rust constants.
const _opSplitAddress = 0;
const _opParseProviders = 1;
const _opEncodeProviders = 2;
const _opUpsertProvider = 3;
const _opJoinHostPort = 4;
const _opParseBootstrap = 5;
const _opEncodeBootstrap = 6;
const _opPresetFromPolicy = 0;
const _opPresetCurrent = 1;
const _opPresetValues = 2;
const _opServerCache = 3;
const _opPresetStorage = 4;
const _opParseUpstreams = 0;
const _opEncodeUpstreams = 1;
const _opValidateUpstream = 2;
const _opNormalizeAddress = 3;
const _opServerHostPort = 4;

/// `6` is "valid" on the wire; the rejection kinds are `0..5`.
const _upstreamOk = 6;

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

class RustDnsConfigCore {
  RustDnsConfigCore._(
    this._tunnel,
    this._server,
    this._providers,
    this._presets,
    this._upstreams,
    this._alloc,
    this._free,
    this.libraryPath,
  );

  final _EntryDart _tunnel;
  final _EntryDart _server;
  final _EntryDart _providers;
  final _EntryDart _presets;
  final _EntryDart _upstreams;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  static RustDnsConfigCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustDnsConfigCore get instance => _instance ??= _load();

  static RustDnsConfigCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_dns_config_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustDnsConfigCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_dns_config_core_tunnel',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_dns_config_core_server',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_dns_config_core_providers',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_dns_config_core_presets',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_dns_config_core_upstreams',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_dns_config_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_dns_config_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'dns config core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    // Cargo turns `diting-dns-config-core` into `libditing_dns_config_core.so` / `.dylib` and
    // `diting_dns_config_core.dll`.
    if (Platform.isAndroid) {
      // 方案 B: all sixteen UI-side kernels share one Android library.
      return 'libditing_kernels.so';
    }
    if (Platform.isLinux) {
      return 'libditing_dns_config_core.so';
    }
    if (Platform.isWindows) return 'diting_dns_config_core.dll';
    if (Platform.isMacOS) return 'libditing_dns_config_core.dylib';
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

  /// Builds the tunnel's `ApplyDNSConfig` document plus the rows the UI shows.
  TunnelDocument buildTunnel({
    required String modeRaw,
    required String selectedProviderId,
    required List<String> smartPredictionProviderIds,
    required List<String> parallelRaceProviderIds,
    required List<String> primaryBackupProviderIds,
    required String? userProvidersJson,
    required bool bootstrapEnabled,
    required List<String> bootstrapPresetIds,
    required String? bootstrapCustomJson,
    required String blockResponseModeRaw,
    required bool cacheEnabled,
    required String cacheModeRaw,
    required int cacheMaxTtlSeconds,
    required int cacheFixedTtlSeconds,
    required bool cacheMinTtlEnabled,
    required int cacheMinTtlSeconds,
    required bool cacheStaleFallbackEnabled,
    required int cacheStaleFallbackSeconds,
    required bool dynamicBlockEnabled,
    required int dynamicBlockRequestThreshold,
    required int dynamicBlockWindowSeconds,
    required int dynamicBlockNxDomainDurationSeconds,
    required List<ProviderRow> presetProviders,
    required List<BootstrapEntryRow> presetBootstrap,
  }) {
    final writer = _PayloadWriter()
      ..u8(
        (bootstrapEnabled ? 0x1 : 0) |
            (cacheEnabled ? 0x2 : 0) |
            (cacheMinTtlEnabled ? 0x4 : 0) |
            (cacheStaleFallbackEnabled ? 0x8 : 0) |
            (dynamicBlockEnabled ? 0x10 : 0),
      )
      ..utf8(modeRaw)
      ..utf8(selectedProviderId)
      ..strings(smartPredictionProviderIds)
      ..strings(parallelRaceProviderIds)
      ..strings(primaryBackupProviderIds)
      ..optionalUtf8(userProvidersJson)
      ..strings(bootstrapPresetIds)
      ..optionalUtf8(bootstrapCustomJson)
      ..utf8(blockResponseModeRaw)
      ..utf8(cacheModeRaw)
      ..i32(cacheMaxTtlSeconds)
      ..i32(cacheFixedTtlSeconds)
      ..i32(cacheMinTtlSeconds)
      ..i32(cacheStaleFallbackSeconds)
      ..i32(dynamicBlockRequestThreshold)
      ..i32(dynamicBlockWindowSeconds)
      ..i32(dynamicBlockNxDomainDurationSeconds)
      ..providerRows(presetProviders)
      ..bootstrapEntryRows(presetBootstrap);
    final reader = _call(_tunnel, writer);
    final mode = reader.string();
    final document = reader.string();
    final providers = reader.providerRows();
    return (
      mode: mode,
      document: document,
      providers: providers,
      bootstrap: reader.bootstrapEntryRows(),
    );
  }

  /// Builds server mode's `applyDnsConfig` document plus the upstreams it picked.
  ///
  /// The resolution mode and its candidate lists use the same scheduling kernel as the tunnel, so
  /// `single` picks one upstream and the three race modes pick their list in engine attempt order.
  ServerDocument buildServer({
    required String resolutionModeRaw,
    required String selectedUpstreamId,
    required List<String> smartPredictionProviderIds,
    required List<String> parallelRaceProviderIds,
    required List<String> primaryBackupProviderIds,
    required int port,
    required bool adBlockEnabled,
    required String cachePresetRaw,
    required bool cacheEnabled,
    required String blockResponseModeRaw,
    required bool dynamicBlockEnabled,
    required int dynamicBlockRequestThreshold,
    required int dynamicBlockWindowSeconds,
    required int dynamicBlockNxDomainDurationSeconds,
    required String? customUpstreamsJson,
    required List<ServerUpstreamRow> presetUpstreams,
  }) {
    final writer = _PayloadWriter()
      ..u8(
        (adBlockEnabled ? 0x1 : 0) |
            (cacheEnabled ? 0x2 : 0) |
            (dynamicBlockEnabled ? 0x4 : 0),
      )
      ..utf8(resolutionModeRaw)
      ..utf8(selectedUpstreamId)
      ..strings(smartPredictionProviderIds)
      ..strings(parallelRaceProviderIds)
      ..strings(primaryBackupProviderIds)
      ..i32(port)
      ..utf8(cachePresetRaw)
      ..utf8(blockResponseModeRaw)
      ..i32(dynamicBlockRequestThreshold)
      ..i32(dynamicBlockWindowSeconds)
      ..i32(dynamicBlockNxDomainDurationSeconds)
      ..optionalUtf8(customUpstreamsJson)
      ..upstreamRows(presetUpstreams);
    final reader = _call(_server, writer);
    final resolvedPort = reader.i32();
    final mode = reader.string();
    final document = reader.string();
    final upstreams = reader.upstreamRows();
    if (upstreams.isEmpty) {
      throw StateError('dns config core returned no upstream');
    }
    return (
      port: resolvedPort,
      mode: mode,
      document: document,
      providers: upstreams,
    );
  }

  /// `_splitAddress`: DoH keeps the text as its URL, everything else becomes host + port.
  ({String url, String host, int port}) splitProviderAddress(
    String protocolStorage,
    String address,
  ) {
    final reader = _call(
      _providers,
      _PayloadWriter()
        ..u8(_opSplitAddress)
        ..utf8(protocolStorage)
        ..utf8(address),
    );
    final url = reader.string();
    final host = reader.string();
    return (url: url, host: host, port: reader.i32());
  }

  List<ProviderRow> parseUserProviders(String? raw) {
    final reader = _call(
      _providers,
      _PayloadWriter()
        ..u8(_opParseProviders)
        ..optionalUtf8(raw),
    );
    return reader.providerRows();
  }

  String encodeUserProviders(List<ProviderRow> rows) {
    final reader = _call(
      _providers,
      _PayloadWriter()
        ..u8(_opEncodeProviders)
        ..providerRows(rows),
    );
    return reader.string();
  }

  List<ProviderRow> upsertUserProvider(
    List<ProviderRow> rows, {
    required String id,
    required String name,
    required String protocolStorage,
    required String address,
  }) {
    final writer = _PayloadWriter()
      ..u8(_opUpsertProvider)
      ..providerRows(rows)
      ..utf8(id)
      ..utf8(name)
      ..utf8(protocolStorage)
      ..utf8(address);
    return _call(_providers, writer).providerRows();
  }

  /// `host:port`, bracketing a bare IPv6 host so the engine can parse the result.
  String joinHostPort(String host, int port) {
    final reader = _call(
      _providers,
      _PayloadWriter()
        ..u8(_opJoinHostPort)
        ..utf8(host)
        ..i32(port),
    );
    return reader.string();
  }

  /// `bootstrap_custom_json` rows, including the `enabled` flag the settings page toggles.
  List<BootstrapRow> parseCustomBootstrap(String? raw) {
    final reader = _call(
      _providers,
      _PayloadWriter()
        ..u8(_opParseBootstrap)
        ..optionalUtf8(raw),
    );
    return reader.bootstrapCustomRows();
  }

  String encodeCustomBootstrap(List<BootstrapRow> rows) {
    final reader = _call(
      _providers,
      _PayloadWriter()
        ..u8(_opEncodeBootstrap)
        ..bootstrapCustomRows(rows),
    );
    return reader.string();
  }

  /// `_opPresetFromPolicy`: which preset the raw cache keys describe.
  int cachePresetFromPolicy({
    required String mode,
    required int maxTtlSeconds,
    required bool minTtlEnabled,
    required int minTtlSeconds,
    required bool staleFallbackEnabled,
    required int staleFallbackSeconds,
  }) => _presetOf(
    _opPresetFromPolicy,
    null,
    mode: mode,
    maxTtlSeconds: maxTtlSeconds,
    minTtlEnabled: minTtlEnabled,
    minTtlSeconds: minTtlSeconds,
    staleFallbackEnabled: staleFallbackEnabled,
    staleFallbackSeconds: staleFallbackSeconds,
  );

  /// The stored preset when it parses, otherwise the derived one.
  int currentCachePreset(
    String? presetRaw, {
    required String mode,
    required int maxTtlSeconds,
    required bool minTtlEnabled,
    required int minTtlSeconds,
    required bool staleFallbackEnabled,
    required int staleFallbackSeconds,
  }) => _presetOf(
    _opPresetCurrent,
    presetRaw,
    mode: mode,
    maxTtlSeconds: maxTtlSeconds,
    minTtlEnabled: minTtlEnabled,
    minTtlSeconds: minTtlSeconds,
    staleFallbackEnabled: staleFallbackEnabled,
    staleFallbackSeconds: staleFallbackSeconds,
  );

  int _presetOf(
    int op,
    String? presetRaw, {
    required String mode,
    required int maxTtlSeconds,
    required bool minTtlEnabled,
    required int minTtlSeconds,
    required bool staleFallbackEnabled,
    required int staleFallbackSeconds,
  }) {
    final writer = _PayloadWriter()..u8(op);
    if (op == _opPresetCurrent) {
      writer.optionalUtf8(presetRaw);
    }
    writer
      ..utf8(mode)
      ..i32(maxTtlSeconds)
      ..flag(minTtlEnabled)
      ..i32(minTtlSeconds)
      ..flag(staleFallbackEnabled)
      ..i32(staleFallbackSeconds);
    return _call(_presets, writer).u8();
  }

  /// The nine values a preset writes into the prefs.
  CacheValues presetValues(int index) => _readCacheValues(
    _call(
      _presets,
      _PayloadWriter()
        ..u8(_opPresetValues)
        ..u8(index),
    ),
  );

  /// Server mode's cache document: the preset's values plus its negative TTL.
  ({CacheValues values, int negativeTtlSeconds}) serverCache(String presetRaw) {
    final reader = _call(
      _presets,
      _PayloadWriter()
        ..u8(_opServerCache)
        ..utf8(presetRaw),
    );
    return (values: _readCacheValues(reader), negativeTtlSeconds: reader.i32());
  }

  /// The prefs spelling of a preset index.
  String presetStorage(int index) => _call(
    _presets,
    _PayloadWriter()
      ..u8(_opPresetStorage)
      ..u8(index),
  ).string();

  CacheValues _readCacheValues(_PayloadReader reader) {
    final mode = reader.string();
    final maxTtlSeconds = reader.i32();
    final fixedTtlSeconds = reader.i32();
    final minTtlEnabled = reader.flag();
    final minTtlSeconds = reader.i32();
    final staleFallbackEnabled = reader.flag();
    return (
      mode: mode,
      maxTtlSeconds: maxTtlSeconds,
      fixedTtlSeconds: fixedTtlSeconds,
      minTtlEnabled: minTtlEnabled,
      minTtlSeconds: minTtlSeconds,
      staleFallbackEnabled: staleFallbackEnabled,
      staleFallbackSeconds: reader.i32(),
    );
  }

  List<ServerUpstreamRow> parseCustomUpstreams(String? raw) {
    final reader = _call(
      _upstreams,
      _PayloadWriter()
        ..u8(_opParseUpstreams)
        ..optionalUtf8(raw),
    );
    return reader.upstreamRows();
  }

  String encodeCustomUpstreams(List<ServerUpstreamRow> rows) {
    final reader = _call(
      _upstreams,
      _PayloadWriter()
        ..u8(_opEncodeUpstreams)
        ..upstreamRows(rows),
    );
    return reader.string();
  }

  /// Null when the input is usable; otherwise the reason, which the caller localises.
  UpstreamRejection? validateUpstream({
    required String name,
    required String protocolStorage,
    required String address,
    required int port,
  }) {
    final reader = _call(
      _upstreams,
      _PayloadWriter()
        ..u8(_opValidateUpstream)
        ..utf8(name)
        ..utf8(protocolStorage)
        ..utf8(address)
        ..i32(port),
    );
    final kind = reader.u8();
    if (kind == _upstreamOk) return null;
    return kind < UpstreamRejection.values.length
        ? UpstreamRejection.values[kind]
        : UpstreamRejection.addressRequired;
  }

  /// Non-DoH addresses are stored bare, so an IPv6 paste keeps its brackets only in the UI.
  String normalizeUpstreamAddress(String protocolStorage, String address) {
    final reader = _call(
      _upstreams,
      _PayloadWriter()
        ..u8(_opNormalizeAddress)
        ..utf8(protocolStorage)
        ..utf8(address),
    );
    return reader.string();
  }

  /// The document's `server` field for a server-mode upstream.
  String serverHostPort(String address, int port) {
    final reader = _call(
      _upstreams,
      _PayloadWriter()
        ..u8(_opServerHostPort)
        ..utf8(address)
        ..i32(port),
    );
    return reader.string();
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
        throw StateError('dns config core rejected the payload');
      }
      final reader = _PayloadReader(
        Uint8List.fromList(outputPtr.asTypedList(outputLength)),
      );
      if (reader.u32() != _payloadMagic) {
        throw const FormatException('dns config core payload magic mismatch');
      }
      final abiVersion = reader.u32();
      if (abiVersion != _abiVersion) {
        throw FormatException(
          'dns config core payload abi $abiVersion, expected $_abiVersion',
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
