/// The native captive-portal evaluator: the Rust crate in `rust/diting-captive-core`, loaded over
/// `dart:ffi`.
///
/// The `generate_204` probe and the platform's capability bits are I/O and stay in Dart/Kotlin; this
/// bridge hands the normalized probe to the crate, which owns the open / portal / unknown judgement
/// and the "suspend blocking" gate.
///
/// Payloads are JSON and the header stays fixed — `magic "DCP1" | abi`; `_abiVersion` must match
/// `ABI_VERSION` in `rust/diting-captive-core/src/ffi.rs`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-captive-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DCP1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31504344;

/// Fixed header width: magic plus ABI version.
const _headerBytes = 8;

/// Explicit library path, for a dev build or a test runner outside the app bundle.
const _pathVariable = 'DITING_CAPTIVE_CORE_LIB';

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

class RustCaptiveCore {
  RustCaptiveCore._(this._call, this._alloc, this._free, this.libraryPath);

  final _EntryDart _call;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  static RustCaptiveCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustCaptiveCore get instance => _instance ??= _load();

  static RustCaptiveCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_captive_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustCaptiveCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_captive_core_call',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_captive_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_captive_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'captive core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    if (Platform.isAndroid) return 'libditing_kernels.so';
    if (Platform.isLinux) return 'libditing_captive_core.so';
    if (Platform.isWindows) return 'diting_captive_core.dll';
    if (Platform.isMacOS) return 'libditing_captive_core.dylib';
    return null;
  }

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

  /// Judges one `generate_204` probe: `state` (open/portal/unknown), `portalUrl`, `suspendBlocking`.
  Map<String, Object?> evaluate({
    int? statusCode,
    String? redirectUrl,
    bool? bodyMatchesExpected,
  }) => call({
    'op': 'captive.evaluate',
    'probe': {
      'statusCode': statusCode,
      'redirectUrl': redirectUrl,
      'bodyMatchesExpected': bodyMatchesExpected,
    },
  });

  /// Parses the RFC 8910 `Captive-Portal` option into a URL (`null` when it is not a usable http(s)
  /// URL).
  String? parseOption(String option) {
    final answer = call({'op': 'captive.parseOption', 'option': option});
    final url = answer['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// Combines the platform capability bits with the probe verdict.
  Map<String, Object?> gate({
    required bool networkValidated,
    required bool captiveCapability,
    int? statusCode,
    String? redirectUrl,
    bool? bodyMatchesExpected,
  }) => call({
    'op': 'captive.gate',
    'networkValidated': networkValidated,
    'captiveCapability': captiveCapability,
    'probe': {
      'statusCode': statusCode,
      'redirectUrl': redirectUrl,
      'bodyMatchesExpected': bodyMatchesExpected,
    },
  });

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) {
    final bytes = utf8.encode(jsonEncode(request));
    final input = _alloc(bytes.length);
    if (input == nullptr) {
      throw StateError(
        'captive core: native allocation of ${bytes.length} bytes failed',
      );
    }
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = _call(input, bytes.length, outLength);
      if (output == nullptr) {
        throw StateError('captive core: native call rejected the payload');
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
        'captive core: truncated payload (${payload.length} bytes)',
      );
    }
    final header = ByteData.sublistView(payload, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _payloadMagic) {
      throw StateError('captive core: unexpected payload magic');
    }
    if (header.getUint32(4, Endian.little) != _abiVersion) {
      throw StateError('captive core: payload abi mismatch');
    }
    final decoded = jsonDecode(utf8.decode(payload.sublist(_headerBytes)));
    if (decoded is! Map<String, Object?>) {
      throw StateError('captive core: payload is not an object');
    }
    return decoded;
  }
}
