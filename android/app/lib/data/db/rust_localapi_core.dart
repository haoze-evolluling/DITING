/// The native local-API policy kernel: the Rust crate in `rust/diting-localapi-core`, loaded over
/// `dart:ffi`.
///
/// The HTTP transport is the app's own `HttpServer`; this bridge only asks the crate the two
/// questions that keep the API safe — is loopback binding/allowed, and is the token right — plus the
/// read-only route table. `_abiVersion` must match `ABI_VERSION` in
/// `rust/diting-localapi-core/src/ffi.rs`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-localapi-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DLA1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31414C44;

const _headerBytes = 8;
const _pathVariable = 'DITING_LOCALAPI_CORE_LIB';

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _EntryNative = Pointer<Uint8> Function(
  Pointer<Uint8>,
  Size,
  Pointer<Size>,
);
typedef _EntryDart = Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>);
typedef _AllocNative = Pointer<Uint8> Function(Size);
typedef _AllocDart = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>, Size);
typedef _FreeDart = void Function(Pointer<Uint8>, int);

class RustLocalApiCore {
  RustLocalApiCore._(this._call, this._alloc, this._free, this.libraryPath);

  final _EntryDart _call;
  final _AllocDart _alloc;
  final _FreeDart _free;
  final String libraryPath;

  static RustLocalApiCore? _instance;

  static RustLocalApiCore get instance => _instance ??= _load();

  static RustLocalApiCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library
            .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
              'diting_localapi_core_abi_version',
            )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        return RustLocalApiCore._(
          library.lookupFunction<_EntryNative, _EntryDart>(
            'diting_localapi_core_call',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_localapi_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_localapi_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'localapi core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  static String? _libraryName() {
    // Android bundles the umbrella library; the other hosts use the standalone crate artifact.
    if (Platform.isAndroid) return 'libditing_kernels.so';
    if (Platform.isLinux) return 'libditing_localapi_core.so';
    if (Platform.isWindows) return 'diting_localapi_core.dll';
    if (Platform.isMacOS) return 'libditing_localapi_core.dylib';
    return null;
  }

  static Iterable<String> _libraryCandidates() sync* {
    final explicit = Platform.environment[_pathVariable];
    if (explicit != null && explicit.isNotEmpty) {
      yield explicit;
    }
    final libraryName = _libraryName();
    if (libraryName == null) return;
    yield libraryName;
    var directory = Directory.current;
    for (var depth = 0; depth < 6; depth++) {
      for (final profile in const ['release', 'debug']) {
        yield '${directory.path}/rust/target/$profile/$libraryName';
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return;
      directory = parent;
    }
  }

  /// `true` when [bind] is a loopback literal the API may bind to.
  bool validateBind(String bind) => call({
    'op': 'localapi.validateBind',
    'bind': bind,
  })['ok'] == true;

  /// `"allow"` / `"unauthorized"` / `"not_loopback"`.
  String authorize({
    required String bind,
    required String clientIp,
    required String expectedToken,
    String? token,
  }) =>
      (call({
            'op': 'localapi.authorize',
            'bind': bind,
            'clientIp': clientIp,
            'expectedToken': expectedToken,
            'token': token,
          })['decision'] as String?) ??
          'unauthorized';

  /// `"found"` (with `route`), `"method_not_allowed"` or `"not_found"`.
  Map<String, Object?> route(String method, String path) =>
      call({'op': 'localapi.route', 'method': method, 'path': path});

  Map<String, Object?> call(Map<String, Object?> request) {
    final bytes = utf8.encode(jsonEncode(request));
    final input = _alloc(bytes.length);
    if (input == nullptr) {
      throw StateError('localapi core: allocation failed');
    }
    final outLength = _alloc(sizeOf<Size>()).cast<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = _call(input, bytes.length, outLength);
      if (output == nullptr) {
        throw StateError('localapi core: native call rejected the payload');
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
      throw StateError('localapi core: truncated payload');
    }
    final header = ByteData.sublistView(payload, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _payloadMagic) {
      throw StateError('localapi core: unexpected payload magic');
    }
    if (header.getUint32(4, Endian.little) != _abiVersion) {
      throw StateError('localapi core: payload abi mismatch');
    }
    final decoded = jsonDecode(utf8.decode(payload.sublist(_headerBytes)));
    if (decoded is! Map<String, Object?>) {
      throw StateError('localapi core: payload is not an object');
    }
    return decoded;
  }
}
