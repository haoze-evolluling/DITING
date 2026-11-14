/// The native DNS-leak evaluator: the Rust crate in `rust/diting-leak-core`, loaded over `dart:ffi`.
///
/// The probe (a fingerprint TXT query and the tunnel's egress counters) is platform I/O and stays in
/// Kotlin/Dart; this bridge only hands the normalized outcome to the crate, which owns the
/// pass / leak / unknown verdict so the page and the health score share one implementation.
///
/// Payloads are JSON and the header stays fixed — `magic "DLK1" | abi`; `_abiVersion` must match
/// `ABI_VERSION` in `rust/diting-leak-core/src/ffi.rs`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-leak-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DLK1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x314B4C44;

/// Fixed header width: magic plus ABI version.
const _headerBytes = 8;

/// Explicit library path, for a dev build or a test runner outside the app bundle.
const _pathVariable = 'DITING_LEAK_CORE_LIB';

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

class RustLeakCore {
  RustLeakCore._(this._call, this._alloc, this._free, this.libraryPath);

  final _EntryDart _call;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  static RustLeakCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustLeakCore get instance => _instance ??= _load();

  static RustLeakCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_leak_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustLeakCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_leak_core_call',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_leak_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_leak_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'leak core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    if (Platform.isAndroid) return 'libditing_kernels.so';
    if (Platform.isLinux) return 'libditing_leak_core.so';
    if (Platform.isWindows) return 'diting_leak_core.dll';
    if (Platform.isMacOS) return 'libditing_leak_core.dylib';
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

  /// Judges one normalized probe: answers `status` (pass/leak/unknown) and `reason`.
  Map<String, Object?> evaluate({
    String? observedExitId,
    String? expectedExitId,
    bool plaintextDnsSeen = false,
    bool? usedConfiguredUpstream,
  }) => call({
    'op': 'leak.evaluate',
    'probe': {
      'observedExitId': observedExitId,
      'expectedExitId': expectedExitId,
      'plaintextDnsSeen': plaintextDnsSeen,
      'usedConfiguredUpstream': usedConfiguredUpstream,
    },
  });

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) {
    final bytes = utf8.encode(jsonEncode(request));
    final input = _alloc(bytes.length);
    if (input == nullptr) {
      throw StateError(
        'leak core: native allocation of ${bytes.length} bytes failed',
      );
    }
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = _call(input, bytes.length, outLength);
      if (output == nullptr) {
        throw StateError('leak core: native call rejected the payload');
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
      throw StateError('leak core: truncated payload (${payload.length} bytes)');
    }
    final header = ByteData.sublistView(payload, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _payloadMagic) {
      throw StateError('leak core: unexpected payload magic');
    }
    if (header.getUint32(4, Endian.little) != _abiVersion) {
      throw StateError('leak core: payload abi mismatch');
    }
    final decoded = jsonDecode(utf8.decode(payload.sublist(_headerBytes)));
    if (decoded is! Map<String, Object?>) {
      throw StateError('leak core: payload is not an object');
    }
    return decoded;
  }
}
