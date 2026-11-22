library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diting_android/data/db/kernel_core.dart';

const _abiVersion = 1;

const _payloadMagic = 0x31565244;

const _headerBytes = 8;

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
