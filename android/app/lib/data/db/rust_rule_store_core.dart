/// The native rule-store core: the Rust crate in `rust/diting-rule-store-core`, loaded over
/// `dart:ffi`.
///
/// The library is required. [`RustRuleStoreCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first rule page instead of quietly running a second
/// copy of the dedupe rules.
///
/// Payloads are JSON and the header stays fixed — `magic "DRS1" | abi`; `_abiVersion` must match
/// `ABI_VERSION` in `rust/diting-rule-store-core/src/ffi.rs`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-rule-store-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DRS1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31535244;

/// Fixed header width: magic plus ABI version.
const _headerBytes = 8;

/// Explicit library path, for a dev build or a test runner outside the app bundle.
const _pathVariable = 'DITING_RULE_STORE_CORE_LIB';

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

/// Arguments of one planned statement as a `sqflite` argument list.
List<Object?> sqlArgs(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

class RustRuleStoreCore {
  RustRuleStoreCore._(
    this._rows,
    this._plan,
    this._alloc,
    this._free,
    this.libraryPath,
  );

  final _EntryDart _rows;
  final _EntryDart _plan;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  static RustRuleStoreCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustRuleStoreCore get instance => _instance ??= _load();

  static RustRuleStoreCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_rule_store_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustRuleStoreCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_rule_store_core_rows',
          ),
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_rule_store_core_plan',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_rule_store_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_rule_store_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'rule store core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    // Cargo turns `diting-rule-store-core` into `libditing_rule_store_core.so` / `.dylib` and
    // `diting_rule_store_core.dll`.
    if (Platform.isAndroid) {
      // 方案 B: all sixteen UI-side kernels share one Android library.
      return 'libditing_kernels.so';
    }
    if (Platform.isLinux) {
      return 'libditing_rule_store_core.so';
    }
    if (Platform.isWindows) return 'diting_rule_store_core.dll';
    if (Platform.isMacOS) return 'libditing_rule_store_core.dylib';
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

  /// Maps one page of rows to rules: `joined` rows (a joined query) or `rules` plus `sources`
  /// (rules loaded for one app).
  List<Map<String, Object?>> rows({
    required String kind,
    required Map<int, String> subscriptions,
    List<Map<String, Object?>> joined = const [],
    List<Map<String, Object?>> rules = const [],
    List<Map<String, Object?>> sources = const [],
  }) {
    final answer = _call(_rows, {
      'kind': kind,
      'subscriptions': [
        for (final entry in subscriptions.entries)
          {'id': entry.key, 'name': entry.value},
      ],
      if (joined.isNotEmpty) 'joined': joined,
      if (joined.isEmpty) 'rules': rules,
      if (joined.isEmpty) 'sources': sources,
    });
    return [
      for (final rule in answer['rules'] as List? ?? const [])
        (rule as Map).cast<String, Object?>(),
    ];
  }

  /// Statement and predicate plans; `op` decides the request shape (see the Rust `ffi` module).
  Map<String, Object?> plan(Map<String, Object?> request) => _call(_plan, request);

  Map<String, Object?> _call(
    _EntryDart entry,
    Map<String, Object?> request,
  ) {
    final bytes = utf8.encode(jsonEncode(request));
    final input = _alloc(bytes.length);
    if (input == nullptr) {
      throw StateError('rule store core: native allocation of ${bytes.length} bytes failed');
    }
    // The out-length slot comes from the same allocator, so this file needs no second `ffi` import.
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = entry(input, bytes.length, outLength);
      if (output == nullptr) {
        throw StateError('rule store core: native call rejected the payload');
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
      throw StateError('rule store core: truncated payload (${payload.length} bytes)');
    }
    final header = ByteData.sublistView(payload, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _payloadMagic) {
      throw StateError('rule store core: unexpected payload magic');
    }
    if (header.getUint32(4, Endian.little) != _abiVersion) {
      throw StateError('rule store core: payload abi mismatch');
    }
    final decoded = jsonDecode(utf8.decode(payload.sublist(_headerBytes)));
    if (decoded is! Map<String, Object?>) {
      throw StateError('rule store core: payload is not an object');
    }
    return decoded;
  }
}
