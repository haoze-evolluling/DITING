/// The native rule-version core: `rust/diting-rule-version-core`, loaded over `dart:ffi`.
///
/// Only the two pure decisions live in Rust (diff and bounded history). The database and the
/// content hash stay here, but the diff the preview shows and the history that gets trimmed are the
/// same implementation, so a rollback preview can never disagree with what was stored.
///
/// Payload: `magic "DRV1"(u32 LE) | abi(u32 LE) | JSON`. `_abiVersion` must match `ABI_VERSION`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Must match `ABI_VERSION` in `rust/diting-rule-version-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DRV1"` as a little-endian u32.
const _payloadMagic = 0x31565244;

const _pathVariable = 'DITING_RULE_VERSION_CORE_LIB';

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _CallNative =
    Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>);
typedef _CallDart = Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>);
typedef _AllocNative = Pointer<Uint8> Function(Size);
typedef _AllocDart = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>, Size);
typedef _FreeDart = void Function(Pointer<Uint8>, int);

/// What changed between two rule sets (mirrors `RuleDiff` in Rust).
class RuleVersionDiff {
  const RuleVersionDiff({
    required this.added,
    required this.removed,
    required this.addedCount,
    required this.removedCount,
    required this.unchangedCount,
    required this.delta,
  });

  final List<String> added;
  final List<String> removed;
  final int addedCount;
  final int removedCount;
  final int unchangedCount;
  final int delta;

  bool get isEmpty =>
      addedCount == 0 && removedCount == 0;
}

/// One stored rule-set snapshot.
class RuleVersionEntry {
  const RuleVersionEntry({
    required this.hash,
    required this.ruleCount,
    required this.createdAt,
  });

  final String hash;
  final int ruleCount;
  final int createdAt;

  Map<String, Object?> toJson() => {
    'hash': hash,
    'ruleCount': ruleCount,
    'createdAt': createdAt,
  };

  factory RuleVersionEntry.fromJson(Map<String, Object?> json) =>
      RuleVersionEntry(
        hash: json['hash'] as String? ?? '',
        ruleCount: (json['ruleCount'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}

class RustRuleVersionCore {
  RustRuleVersionCore._(this._call, this._alloc, this._free, this.libraryPath);

  final _CallDart _call;
  final _AllocDart _alloc;
  final _FreeDart _free;
  final String libraryPath;

  static RustRuleVersionCore? _instance;

  static RustRuleVersionCore get instance => _instance ??= _load();

  static RustRuleVersionCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abi = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'diting_rule_version_core_abi_version',
        )();
        if (abi != _abiVersion) {
          failures.add('$candidate: abi $abi, expected $_abiVersion');
          continue;
        }
        return RustRuleVersionCore._(
          library.lookupFunction<_CallNative, _CallDart>(
            'diting_rule_version_core_call',
          ),
          library.lookupFunction<_AllocNative, _AllocDart>(
            'diting_rule_version_core_alloc',
          ),
          library.lookupFunction<_FreeNative, _FreeDart>(
            'diting_rule_version_core_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'rule-version core unavailable '
      '(${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  /// The diff between two rule lists. Throws [StateError] on a rejected payload.
  RuleVersionDiff diff(List<String> oldRules, List<String> newRules) {
    final answer = _send({
      'op': 'ruleversion.diff',
      'old': oldRules,
      'new': newRules,
    });
    return RuleVersionDiff(
      added: _strings(answer['added']),
      removed: _strings(answer['removed']),
      addedCount: (answer['addedCount'] as num?)?.toInt() ?? 0,
      removedCount: (answer['removedCount'] as num?)?.toInt() ?? 0,
      unchangedCount: (answer['unchangedCount'] as num?)?.toInt() ?? 0,
      delta: (answer['delta'] as num?)?.toInt() ?? 0,
    );
  }

  /// Prepends `hash` to the newest-first `existing` history, skipping an unchanged head and trimming
  /// to `max` (kernel default when null).
  List<RuleVersionEntry> record(
    List<RuleVersionEntry> existing, {
    required String hash,
    required int ruleCount,
    required int createdAt,
    int? max,
  }) {
    final answer = _send({
      'op': 'ruleversion.record',
      'versions': [for (final entry in existing) entry.toJson()],
      'hash': hash,
      'ruleCount': ruleCount,
      'createdAt': createdAt,
      'max': ?max,
    });
    final versions = answer['versions'];
    if (versions is! List) return existing;
    return [
      for (final item in versions)
        if (item is Map) RuleVersionEntry.fromJson(item.cast<String, Object?>()),
    ];
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
        throw StateError('rule-version core returned no payload');
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
      throw const FormatException('rule-version payload magic mismatch');
    }
    final abi = view.getUint32(4, Endian.little);
    if (abi != _abiVersion) {
      throw FormatException('rule-version payload abi $abi, expected $_abiVersion');
    }
    final json = jsonDecode(utf8.decode(payload.sublist(8))) as Map;
    return json.cast<String, Object?>();
  }

  static List<String> _strings(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is String) item,
        ]
      : const [];

  static String? _libraryName() {
    if (Platform.isAndroid) return 'libditing_kernels.so';
    if (Platform.isLinux) return 'libditing_rule_version_core.so';
    if (Platform.isWindows) return 'diting_rule_version_core.dll';
    if (Platform.isMacOS) return 'libditing_rule_version_core.dylib';
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
