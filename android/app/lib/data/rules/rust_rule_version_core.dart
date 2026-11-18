/// The native rule-version core: `rust/diting-rule-version-core`, loaded over `dart:ffi`.
///
/// Only the two pure decisions live in Rust (diff and bounded history). The database and the
/// content hash stay here, but the diff the preview shows and the history that gets trimmed are the
/// same implementation, so a rollback preview can never disagree with what was stored.
///
/// Payload: `magic "DRV1"(u32 LE) | abi(u32 LE) | JSON`. `_abiVersion` must match `ABI_VERSION`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diting_android/data/db/kernel_core.dart';

/// Must match `ABI_VERSION` in `rust/diting-rule-version-core/src/ffi.rs`.
const _abiVersion = 1;

/// `"DRV1"` as a little-endian u32.
const _payloadMagic = 0x31565244;

/// Fixed header width: magic plus ABI version.
const _headerBytes = 8;

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
  RustRuleVersionCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustRuleVersionCore? _instance;

  static RustRuleVersionCore get instance => _instance ??= _load();

  static RustRuleVersionCore _load() => RustRuleVersionCore._(
    KernelCore.load(
      crate: 'diting-rule-version-core',
      payloadMagic: _payloadMagic,
      abiVersion: _abiVersion,
      errorPrefix: 'rule-version core',
    ),
  );

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
    final reply = _core.invoke(utf8.encode(jsonEncode(request)));
    if (reply.length <= _headerBytes) {
      throw StateError('rule-version core returned no payload');
    }
    final view = ByteData.sublistView(reply);
    if (view.getUint32(0, Endian.little) != _payloadMagic) {
      throw const FormatException('rule-version payload magic mismatch');
    }
    final abi = view.getUint32(4, Endian.little);
    if (abi != _abiVersion) {
      throw FormatException('rule-version payload abi $abi, expected $_abiVersion');
    }
    final json = jsonDecode(utf8.decode(reply.sublist(_headerBytes))) as Map;
    return json.cast<String, Object?>();
  }

  static List<String> _strings(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is String) item,
        ]
      : const [];
}
