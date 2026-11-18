/// The native rule-store core: the Rust crate in `rust/diting-rule-store-core`, loaded over
/// `dart:ffi`.
///
/// The library is required. [`RustRuleStoreCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first rule page instead of quietly running a second
/// copy of the dedupe rules.
///
/// Payloads are JSON with the shared kernel header — `magic "DRS1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DRS1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31535244;

/// Arguments of one planned statement as a `sqflite` argument list.
List<Object?> sqlArgs(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

class RustRuleStoreCore {
  RustRuleStoreCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustRuleStoreCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustRuleStoreCore get instance => _instance ??= _load();

  static RustRuleStoreCore _load() => RustRuleStoreCore._(
    KernelCore.load(
      crate: 'diting-rule-store-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'rule store core',
      entries: const ['rows', 'plan'],
    ),
  );

  /// Maps one page of rows to rules: `joined` rows (a joined query) or `rules` plus `sources`
  /// (rules loaded for one app).
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

  /// Statement and predicate plans; `op` decides the request shape (see the Rust `ffi` module).
  Map<String, Object?> plan(Map<String, Object?> request) =>
      _core.call(request, entry: 'plan');
}
