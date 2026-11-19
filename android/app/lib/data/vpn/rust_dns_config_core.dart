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
import 'dart:typed_data';

import 'package:diting_android/data/db/kernel_core.dart';

part 'rust_dns_config_core_build.dart';
part 'rust_dns_config_core_payload.dart';
part 'rust_dns_config_core_records.dart';

/// Must match `ABI_VERSION` in `rust/diting-dns-config-core/src/ffi.rs`.
const _abiVersion = 3;

/// `"DDC1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31434444;

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

class RustDnsConfigCore {
  RustDnsConfigCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustDnsConfigCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustDnsConfigCore get instance => _instance ??= _load();

  static RustDnsConfigCore _load() => RustDnsConfigCore._(
    KernelCore.load(
      crate: 'diting-dns-config-core',
      payloadMagic: _payloadMagic,
      abiVersion: _abiVersion,
      errorPrefix: 'dns config core',
      entries: const ['tunnel', 'server', 'providers', 'presets', 'upstreams'],
    ),
  );

  /// `_splitAddress`: DoH keeps the text as its URL, everything else becomes host + port.
  ({String url, String host, int port}) splitProviderAddress(
    String protocolStorage,
    String address,
  ) {
    final reader = _call(
      'providers',
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
      'providers',
      _PayloadWriter()
        ..u8(_opParseProviders)
        ..optionalUtf8(raw),
    );
    return reader.providerRows();
  }

  String encodeUserProviders(List<ProviderRow> rows) {
    final reader = _call(
      'providers',
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
    return _call('providers', writer).providerRows();
  }

  /// `host:port`, bracketing a bare IPv6 host so the engine can parse the result.
  String joinHostPort(String host, int port) {
    final reader = _call(
      'providers',
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
      'providers',
      _PayloadWriter()
        ..u8(_opParseBootstrap)
        ..optionalUtf8(raw),
    );
    return reader.bootstrapCustomRows();
  }

  String encodeCustomBootstrap(List<BootstrapRow> rows) {
    final reader = _call(
      'providers',
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
    return _call('presets', writer).u8();
  }

  /// The nine values a preset writes into the prefs.
  CacheValues presetValues(int index) => _readCacheValues(
    _call(
      'presets',
      _PayloadWriter()
        ..u8(_opPresetValues)
        ..u8(index),
    ),
  );

  /// Server mode's cache document: the preset's values plus its negative TTL.
  ({CacheValues values, int negativeTtlSeconds}) serverCache(String presetRaw) {
    final reader = _call(
      'presets',
      _PayloadWriter()
        ..u8(_opServerCache)
        ..utf8(presetRaw),
    );
    return (values: _readCacheValues(reader), negativeTtlSeconds: reader.i32());
  }

  /// The prefs spelling of a preset index.
  String presetStorage(int index) => _call(
    'presets',
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
      'upstreams',
      _PayloadWriter()
        ..u8(_opParseUpstreams)
        ..optionalUtf8(raw),
    );
    return reader.upstreamRows();
  }

  String encodeCustomUpstreams(List<ServerUpstreamRow> rows) {
    final reader = _call(
      'upstreams',
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
      'upstreams',
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
      'upstreams',
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
      'upstreams',
      _PayloadWriter()
        ..u8(_opServerHostPort)
        ..utf8(address)
        ..i32(port),
    );
    return reader.string();
  }

  /// Sends one payload to [entry] and checks the reply header.
  _PayloadReader _call(String entry, _PayloadWriter writer) {
    final reply = _core.invoke(writer.finish(), entry: entry);
    if (reply.isEmpty) {
      throw StateError('dns config core rejected the payload');
    }
    final reader = _PayloadReader(reply);
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
  }
}
