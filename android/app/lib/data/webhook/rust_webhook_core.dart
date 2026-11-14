/// The native webhook kernel: `rust/diting-webhook-core`, loaded over `dart:ffi`.
///
/// Signing and the retry decision are pure and live in Rust so the sender and any future consumer
/// cannot disagree. Payload: `magic "DWH1"(u32 LE) | abi(u32 LE) | JSON`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-webhook-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DWH1"` as a little-endian u32.
const _payloadMagic = 0x31485744;

const _pathVariable = 'DITING_WEBHOOK_CORE_LIB';

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _CallNative =
    Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>);
typedef _CallDart = Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>);
typedef _AllocNative = Pointer<Uint8> Function(Size);
typedef _AllocDart = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>, Size);
typedef _FreeDart = void Function(Pointer<Uint8>, int);

/// Whether to retry a failed delivery and how long to wait.
class WebhookRetryDecision {
  const WebhookRetryDecision({required this.retry, required this.delayMs});

  final bool retry;
  final int delayMs;
}

class RustWebhookCore {
  RustWebhookCore._(this._call, this._alloc, this._free, this.libraryPath);

  final _CallDart _call;
  final _AllocDart _alloc;
  final _FreeDart _free;
  final String libraryPath;

  static RustWebhookCore? _instance;

  static RustWebhookCore get instance => _instance ??= _load();

  static RustWebhookCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abi = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'diting_webhook_core_abi_version',
        )();
        if (abi != _abiVersion) {
          failures.add('$candidate: abi $abi, expected $_abiVersion');
          continue;
        }
        return RustWebhookCore._(
          library.lookupFunction<_CallNative, _CallDart>(
            'diting_webhook_core_call',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_webhook_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_webhook_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'webhook core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  /// The `sha256=<hex>` header value for a body delivered at [timestamp].
  String sign({
    required String secret,
    required String body,
    required int timestamp,
  }) {
    final answer = _send({
      'op': 'webhook.sign',
      'secret': secret,
      'body': body,
      'timestamp': timestamp,
    });
    return answer['signature'] as String? ?? '';
  }

  WebhookRetryDecision retry({
    required int attempt,
    int? status,
    int baseMs = 1000,
    int maxMs = 30000,
    int maxAttempts = 3,
  }) {
    final answer = _send({
      'op': 'webhook.retry',
      'attempt': attempt,
      'status': ?status,
      'baseMs': baseMs,
      'maxMs': maxMs,
      'maxAttempts': maxAttempts,
    });
    return WebhookRetryDecision(
      retry: answer['retry'] as bool? ?? false,
      delayMs: (answer['delayMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> _send(Map<String, Object?> request) {
    final bytes = utf8.encode(jsonEncode(request));
    final inputPtr = bytes.isEmpty ? nullptr : _alloc(bytes.length);
    final outLenPtr = _alloc(sizeOf<Size>()).cast<Size>();
    Pointer<Uint8> outputPtr = nullptr;
    var outputLength = 0;
    try {
      if (bytes.isNotEmpty) {
        inputPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      outputPtr = _call(inputPtr, bytes.length, outLenPtr);
      outputLength = outLenPtr.value;
      if (outputPtr == nullptr || outputLength <= 8) {
        throw StateError('webhook core returned no payload');
      }
      final payload = outputPtr.asTypedList(outputLength);
      return _decode(payload);
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, bytes.length);
      _free(outLenPtr.cast<Uint8>(), sizeOf<Size>());
      if (outputPtr != nullptr && outputLength > 0) {
        _free(outputPtr, outputLength);
      }
    }
  }

  static Map<String, Object?> _decode(Uint8List payload) {
    final view = ByteData.sublistView(payload);
    if (view.getUint32(0, Endian.little) != _payloadMagic) {
      throw const FormatException('webhook payload magic mismatch');
    }
    final abi = view.getUint32(4, Endian.little);
    if (abi != _abiVersion) {
      throw FormatException('webhook payload abi $abi, expected $_abiVersion');
    }
    final json = jsonDecode(utf8.decode(payload.sublist(8))) as Map;
    return json.cast<String, Object?>();
  }

  static String? _libraryName() {
    if (Platform.isAndroid) return 'libditing_kernels.so';
    if (Platform.isLinux) return 'libditing_webhook_core.so';
    if (Platform.isWindows) return 'diting_webhook_core.dll';
    if (Platform.isMacOS) return 'libditing_webhook_core.dylib';
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
}
