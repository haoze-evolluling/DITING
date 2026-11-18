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
    required int abiVersion,
    required String errorPrefix,
    required Map<String, _EntryDart> entries,
    required _AllocDart alloc,
    required _FreeDart free,
  }) : _payloadMagic = payloadMagic,
       _abiVersion = abiVersion,
       _errorPrefix = errorPrefix,
       _entries = entries,
       _alloc = alloc,
       _free = free;

  /// Resolved library path, surfaced in diagnostics.
  final String libraryPath;

  final Map<String, _EntryDart> _entries;
  final int _payloadMagic;
  final int _abiVersion;
  final String _errorPrefix;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// Loads the library exporting [crate]'s symbols (`diting-leak-core`).
  ///
  /// [entries] are the symbol suffixes after the crate's name, e.g. `call` for
  /// `diting_leak_core_call`. [payloadMagic] is the reply header's first field, e.g. `"DLK1"` read
  /// as a little-endian u32. [abiVersion] overrides the shared header ABI for the few kernels that
  /// version their payloads independently.
  static KernelCore load({
    required String crate,
    required int payloadMagic,
    required String errorPrefix,
    int abiVersion = kernelAbiVersion,
    List<String> entries = const ['call'],
  }) {
    final symbolBase = crate.replaceAll('-', '_');
    final failures = <String>[];
    for (final candidate in _libraryCandidates(symbolBase)) {
      try {
        final library = DynamicLibrary.open(candidate);
        final foundAbiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              '${symbolBase}_abi_version',
            )();
        if (foundAbiVersion != abiVersion) {
          failures.add(
            '$candidate: abi $foundAbiVersion, expected $abiVersion',
          );
          continue;
        }
        return KernelCore._(
          libraryPath: candidate,
          payloadMagic: payloadMagic,
          abiVersion: abiVersion,
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

  /// Raw round trip: [payload] in, the core's reply bytes out (header included).
  ///
  /// An empty list means the core returned no payload; callers decide whether that is an error.
  Uint8List invoke(Uint8List payload, {String entry = 'call'}) {
    final entryPoint = _entries[entry];
    if (entryPoint == null) {
      throw StateError('$_errorPrefix: no "$entry" entry point');
    }
    final input = payload.isEmpty ? nullptr : _alloc(payload.length);
    if (payload.isNotEmpty && input == nullptr) {
      throw StateError(
        '$_errorPrefix: native allocation of ${payload.length} bytes failed',
      );
    }
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      if (payload.isNotEmpty) {
        input.asTypedList(payload.length).setAll(0, payload);
      }
      final output = entryPoint(input, payload.length, outLength);
      final length = outLength.value;
      if (output == nullptr || length == 0) return Uint8List(0);
      try {
        return Uint8List.fromList(output.asTypedList(length));
      } finally {
        _free(output, length);
      }
    } finally {
      _free(outLength.cast<Uint8>(), sizeOf<Size>());
      if (payload.isNotEmpty) _free(input, payload.length);
    }
  }

  /// One JSON request in, one decoded JSON object out; [entry] names the symbol suffix.
  Map<String, Object?> call(
    Map<String, Object?> request, {
    String entry = 'call',
  }) {
    final reply = invoke(utf8.encode(jsonEncode(request)), entry: entry);
    if (reply.isEmpty) {
      throw StateError('$_errorPrefix: native call rejected the payload');
    }
    return _decode(reply);
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
    if (header.getUint32(4, Endian.little) != _abiVersion) {
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
