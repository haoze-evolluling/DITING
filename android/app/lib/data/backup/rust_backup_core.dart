/// The native backup core: the Rust crate in `rust/diting-backup-core`, loaded over `dart:ffi`.
///
/// The library is required. [`RustBackupCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first export instead of quietly writing a file with
/// the old code.
///
/// The payload is JSON: the backup file itself is JSON, so a binary layout would only re-encode it
/// on both sides. The fixed header stays — `magic "DBK1" | abi` — and `_abiVersion` must match
/// `ABI_VERSION` in `rust/diting-backup-core/src/ffi.rs`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-backup-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DBK1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x314b4244;

/// Fixed header width: magic plus ABI version.
const _headerBytes = 8;

/// Explicit library path, for a dev build or a test runner outside the app bundle.
const _pathVariable = 'DITING_BACKUP_CORE_LIB';

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

class RustBackupCore {
  RustBackupCore._(
    this._export,
    this._import,
    this._alloc,
    this._free,
    this.libraryPath,
  );

  final _EntryDart _export;
  final _EntryDart _import;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  static RustBackupCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustBackupCore get instance => _instance ??= _load();

  static RustBackupCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_backup_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustBackupCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_backup_core_export',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_backup_core_import',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_backup_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_backup_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'backup core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    // Cargo turns `diting-backup-core` into `libditing_backup_core.so` / `.dylib` and
    // `diting_backup_core.dll`.
    if (Platform.isAndroid) {
      // 方案 B: all sixteen UI-side kernels share one Android library.
      return 'libditing_kernels.so';
    }
    if (Platform.isLinux) {
      return 'libditing_backup_core.so';
    }
    if (Platform.isWindows) return 'diting_backup_core.dll';
    if (Platform.isMacOS) return 'libditing_backup_core.dylib';
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

  /// Builds the backup document: `{nowMs, groups, fields}` in, `{content, included, counts,
  /// skipped}` out.
  Map<String, Object?> exportDocument(Map<String, Object?> request) =>
      _call(_export, request);

  /// Validates and merges a backup file: `{content, nowMs, hasDatabase, current}` in, the import
  /// plan out (see `rust/diting-backup-core/src/import.rs`).
  Map<String, Object?> importDocument(Map<String, Object?> request) =>
      _call(_import, request);

  Map<String, Object?> _call(
    _EntryDart entry,
    Map<String, Object?> request,
  ) {
    final bytes = utf8.encode(jsonEncode(request));
    final input = _alloc(bytes.length);
    if (input == nullptr) {
      throw StateError('backup core: native allocation of ${bytes.length} bytes failed');
    }
    // The out-length slot comes from the same allocator, so this file needs no second `ffi` import.
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = entry(input, bytes.length, outLength);
      if (output == nullptr) {
        throw StateError('backup core: native call rejected the payload');
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
      throw StateError('backup core: truncated payload (${payload.length} bytes)');
    }
    final header = ByteData.sublistView(payload, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _payloadMagic) {
      throw StateError('backup core: unexpected payload magic');
    }
    if (header.getUint32(4, Endian.little) != _abiVersion) {
      throw StateError('backup core: payload abi mismatch');
    }
    final decoded = jsonDecode(utf8.decode(payload.sublist(_headerBytes)));
    if (decoded is! Map<String, Object?>) {
      throw StateError('backup core: payload is not an object');
    }
    return decoded;
  }
}
