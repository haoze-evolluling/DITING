library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31535244;

List<Object?> sqlArgs(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

class RustRuleStoreCore {
  RustRuleStoreCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustRuleStoreCore? _instance;

  static RustRuleStoreCore get instance => _instance ??= _load();

  static RustRuleStoreCore _load() => RustRuleStoreCore._(
    KernelCore.load(
      crate: 'diting-rule-store-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'rule store core',
      entries: const ['rows', 'plan'],
    ),
  );

  List<Map<String, Object?>> rows({
    required String kind,
    required Map<int, String> subscriptions,
    List<Map<String, Object?>> joined = const [],
    List<Map<String, Object?>> rules = const [],
    List<Map<String, Object?>> sources = const [],
  }) {
    final answer = _core.call({
      'kind': kind,
      'subscriptions': [
        for (final entry in subscriptions.entries)
          {'id': entry.key, 'name': entry.value},
      ],
      if (joined.isNotEmpty) 'joined': joined,
      if (joined.isEmpty) 'rules': rules,
      if (joined.isEmpty) 'sources': sources,
    }, entry: 'rows');
    return [
      for (final rule in answer['rules'] as List? ?? const [])
        (rule as Map).cast<String, Object?>(),
    ];
  }

  Map<String, Object?> plan(Map<String, Object?> request) =>
      _core.call(request, entry: 'plan');
}
