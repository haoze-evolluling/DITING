/// The native outbound-proxy configuration core: the Rust crate in
/// `rust/diting-outbound-proxy-core`, loaded over `dart:ffi`.
///
/// SharedPreferences, the Keystore, PackageManager, HTTP and the localized sentences stay in
/// Dart/Kotlin; this core imports the engine's protocol/host/port/credential/scope rules and owns
/// the app package checks, target filtering and the engine JSON. The library is required:
/// [`RustOutboundProxyCore.instance`] throws when the artifact is missing, the platform is
/// unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails the settings page instead of accepting a config the engine
/// would reject.
///
/// Payloads are JSON and the header stays fixed — `magic "DOP1" | abi`; `_abiVersion` must match
/// `ABI_VERSION` in `rust/diting-outbound-proxy-core/src/ffi.rs`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-outbound-proxy-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DOP1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31504F44;

/// Fixed header width: magic plus ABI version.
const _headerBytes = 8;

/// Explicit library path, for a dev build or a test runner outside the app bundle.
const _pathVariable = 'DITING_OUTBOUND_PROXY_CORE_LIB';

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

class RustOutboundProxyCore {
  RustOutboundProxyCore._(
    this._call,
    this._alloc,
    this._free,
    this.libraryPath,
  );

  final _EntryDart _call;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  static RustOutboundProxyCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustOutboundProxyCore get instance => _instance ??= _load();

  static RustOutboundProxyCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_outbound_proxy_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustOutboundProxyCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_outbound_proxy_core_call',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_outbound_proxy_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_outbound_proxy_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'outbound proxy core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    // Cargo turns `diting-outbound-proxy-core` into `libditing_outbound_proxy_core.so` / `.dylib`
    // and `diting_outbound_proxy_core.dll`.
    if (Platform.isAndroid) {
      // 方案 B: all sixteen UI-side kernels share one Android library.
      return 'libditing_kernels.so';
    }
    if (Platform.isLinux) {
      return 'libditing_outbound_proxy_core.so';
    }
    if (Platform.isWindows) return 'diting_outbound_proxy_core.dll';
    if (Platform.isMacOS) return 'libditing_outbound_proxy_core.dylib';
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

  /// First rejected field as a stable token, or null when the config is acceptable.
  String? validationError(
    Map<String, Object?> config, {
    String? selfPackage,
    List<String>? installedPackages,
  }) =>
      call({
            'op': 'validate',
            'config': config,
            'selfPackage': selfPackage,
            'installedPackages': installedPackages,
          })['code']
          as String?;

  /// The exact JSON `Engine.configureOutboundProxy` decodes.
  String engineJson(Map<String, Object?> config) =>
      call({'op': 'engineJson', 'config': config})['json'] as String;

  /// Target packages after dropping blanks/the proxy app, deduplicated and sorted.
  List<String> effectiveTargets(Map<String, Object?> config) => [
    for (final value
        in call({'op': 'effectiveTargets', 'config': config})['values'] as List)
      value as String,
  ];

  /// Shared enum fallback: `socks5` / `http`, anything else becomes `socks5`.
  String normalizeProtocol(String value) =>
      call({'op': 'normalizeProtocol', 'value': value})['value'] as String;

  /// Shared enum fallback: `apps` exactly, anything else becomes `all`.
  String normalizeScope(String value) =>
      call({'op': 'normalizeScope', 'value': value})['value'] as String;

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) {
    final bytes = utf8.encode(jsonEncode(request));
    final input = _alloc(bytes.length);
    if (input == nullptr) {
      throw StateError(
        'outbound proxy core: native allocation of ${bytes.length} bytes failed',
      );
    }
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = _call(input, bytes.length, outLength);
      if (output == nullptr) {
        throw StateError(
          'outbound proxy core: native call rejected the payload',
        );
      }
      final length = outLength.value;
      try {
        return _decode(output.asTypedList(length));
      } finally {
        _free(output, length);
      }
    } finally {
      _free(outLength.cast<Uint8>(), sizeOf<Size>());
      _free(input, bytes.length);
    }
  }

  Map<String, Object?> _decode(Uint8List payload) {
    if (payload.length < _headerBytes) {
      throw StateError(
        'outbound proxy core: truncated payload (${payload.length} bytes)',
      );
    }
    final header = ByteData.sublistView(payload, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _payloadMagic) {
      throw StateError('outbound proxy core: unexpected payload magic');
    }
    if (header.getUint32(4, Endian.little) != _abiVersion) {
      throw StateError('outbound proxy core: payload abi mismatch');
    }
    final decoded = jsonDecode(utf8.decode(payload.sublist(_headerBytes)));
    if (decoded is! Map<String, Object?>) {
      throw StateError('outbound proxy core: payload is not an object');
    }
    return decoded;
  }
}
