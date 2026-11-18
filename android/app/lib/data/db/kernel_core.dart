/// Shared `dart:ffi` plumbing for the UI-side kernels under `rust/`.
///
/// Every kernel library exports the same C ABI — an `abi_version` probe, `alloc`/`free`, and one
/// or more JSON entry points — and every reply carries the fixed header `magic | abi`. Loading,
/// candidate probing and the payload round trip live here; each core file keeps only its crate
/// name, payload magic and request shapes.
///
/// The libraries are required: [KernelCore.load] throws when no candidate has the expected ABI, so
/// a build that forgot `python rust/build_android.py` fails instead of quietly running a second
/// Dart copy of the kernel's rules.
// ignore_for_file: prefer_initializing_formals
// False positive: fields are private `_xxx`, and Dart forbids named parameters starting with `_`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in every kernel's `src/ffi.rs`.
const kernelAbiVersion = 1;

/// Fixed header width: magic plus ABI version.
const _headerBytes = 8;

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

class KernelCore {
  KernelCore._({
    required this.libraryPath,
    required int payloadMagic,
    required String errorPrefix,
    required Map<String, _EntryDart> entries,
    required _AllocDart alloc,
    required _FreeDart free,
  }) : _payloadMagic = payloadMagic,
       _errorPrefix = errorPrefix,
       _entries = entries,
       _alloc = alloc,
       _free = free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  final Map<String, _EntryDart> _entries;
  final int _payloadMagic;
  final String _errorPrefix;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Loads the library exporting [crate]'s symbols (`diting-leak-core`).
  ///
  /// [entries] are the symbol suffixes after the crate's name, e.g. `call` for
  /// `diting_leak_core_call`. [payloadMagic] is the reply header's first field, e.g. `"DLK1"` read
  /// as a little-endian u32.
  static KernelCore load({
    required String crate,
    required int payloadMagic,
    required String errorPrefix,
    List<String> entries = const ['call'],
  }) {
    final symbolBase = crate.replaceAll('-', '_');
    final failures = <String>[];
    for (final candidate in _libraryCandidates(symbolBase)) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              '${symbolBase}_abi_version',
            )();
        if (abiVersion != kernelAbiVersion) {
          failures.add(
            '$candidate: abi $abiVersion, expected $kernelAbiVersion',
          );
          continue;
        }
        return KernelCore._(
          libraryPath: candidate,
          payloadMagic: payloadMagic,
          errorPrefix: errorPrefix,
          entries: {
            for (final entry in entries)
              entry: library.lookupFunction<_EntryNative, _EntryDart>(
                '${symbolBase}_$entry',
              ),
          },
          alloc: library.lookupFunction<_AllocNative, _AllocDart>(
            '${symbolBase}_alloc',
          ),
          free: library.lookupFunction<_FreeNative, _FreeDart>(
            '${symbolBase}_free',
          ),
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      '$errorPrefix unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  /// One JSON request in, one decoded JSON object out; [entry] names the symbol suffix.
  Map<String, Object?> call(
    Map<String, Object?> request, {
    String entry = 'call',
  }) {
    final invoke = _entries[entry];
    if (invoke == null) {
      throw StateError('$_errorPrefix: no "$entry" entry point');
    }
    final bytes = utf8.encode(jsonEncode(request));
    final input = _alloc(bytes.length);
    if (input == nullptr) {
      throw StateError(
        '$_errorPrefix: native allocation of ${bytes.length} bytes failed',
      );
    }
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = invoke(input, bytes.length, outLength);
      if (output == nullptr) {
        throw StateError('$_errorPrefix: native call rejected the payload');
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
        '$_errorPrefix: truncated payload (${payload.length} bytes)',
      );
    }
    final header = ByteData.sublistView(payload, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _payloadMagic) {
      throw StateError('$_errorPrefix: unexpected payload magic');
    }
    if (header.getUint32(4, Endian.little) != kernelAbiVersion) {
      throw StateError('$_errorPrefix: payload abi mismatch');
    }
    final decoded = jsonDecode(utf8.decode(payload.sublist(_headerBytes)));
    if (decoded is! Map<String, Object?>) {
      throw StateError('$_errorPrefix: payload is not an object');
    }
    return decoded;
  }

  static String? _libraryName(String symbolBase) {
    // Cargo turns `diting-leak-core` into `libditing_leak_core.so` / `.dylib` and
    // `diting_leak_core.dll`.
    if (Platform.isAndroid) {
      // 方案 B: all sixteen UI-side kernels share one Android library.
      return 'libditing_kernels.so';
    }
    if (Platform.isLinux) return 'lib$symbolBase.so';
    if (Platform.isWindows) return '$symbolBase.dll';
    if (Platform.isMacOS) return 'lib$symbolBase.dylib';
    return null;
  }

  /// Probe order: explicit path, the packaged library name, then repo build output — the last one
  /// lets `flutter test` on the desktop host exercise the real native path without an APK.
  static Iterable<String> _libraryCandidates(String symbolBase) sync* {
    final explicit =
        Platform.environment['DITING_${symbolBase.toUpperCase()}_LIB'];
    if (explicit != null && explicit.isNotEmpty) {
      yield explicit;
    }
    final libraryName = _libraryName(symbolBase);
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
}
