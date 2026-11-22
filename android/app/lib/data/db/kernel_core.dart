// ignore_for_file: prefer_initializing_formals
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

const kernelAbiVersion = 1;

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

  final String libraryPath;

  final Map<String, _EntryDart> _entries;
  final int _payloadMagic;
  final int _abiVersion;
  final String _errorPrefix;
  final _AllocDart _alloc;
  final _FreeDart _free;

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
    if (Platform.isAndroid) {
      return 'libditing_native.so';
    }
    if (Platform.isLinux) return 'lib$symbolBase.so';
    if (Platform.isWindows) return '$symbolBase.dll';
    if (Platform.isMacOS) return 'lib$symbolBase.dylib';
    return null;
  }

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
