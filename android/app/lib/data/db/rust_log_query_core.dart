/// The native log query core: the Rust crate in `rust/diting-log-query-core`, loaded over
/// `dart:ffi`.
///
/// The library is required. [`RustLogQueryCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first log page instead of quietly running a second
/// copy of the SQL, classification or aggregate rules.
///
/// Payloads are JSON with the shared kernel header — `magic "DLQ1" | abi` (see [KernelCore]).
library;

import 'dart:isolate';

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DLQ1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31514C44;

/// One read statement and its `sqflite` arguments.
class LogQueryPlan {
  const LogQueryPlan(this.sql, this.args);

  final String sql;
  final List<Object?> args;
}

class RustLogQueryCore {
  RustLogQueryCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustLogQueryCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustLogQueryCore get instance => _instance ??= _load();

  static RustLogQueryCore _load() => RustLogQueryCore._(
    KernelCore.load(
      crate: 'diting-log-query-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'log query core',
    ),
  );

  /// Builds one read statement; `params` are spread next to the query name.
  LogQueryPlan plan(String name, [Map<String, Object?> params = const {}]) {
    final answer = call({'op': 'plan', 'name': name, ...params});
    return LogQueryPlan(
      answer['sql']! as String,
      List<Object?>.from(answer['args'] as List? ?? const []),
    );
  }

  /// Parses raw SQLite rows of one kind; `nowMs` is only read by cache rows.
  List<Map<String, Object?>> rows(
    String kind,
    List<Map<String, Object?>> rows, {
    int? nowMs,
  }) {
    if (rows.isEmpty) return const [];
    final answer = call({
      'op': 'rows',
      'kind': kind,
      'rows': rows,
      'nowMs': nowMs,
    });
    return [
      for (final item in answer['items'] as List? ?? const [])
        (item as Map).cast<String, Object?>(),
    ];
  }

  /// One aggregate; `request` carries the already-parsed rows or derived inputs.
  Map<String, Object?> derive(String name, Map<String, Object?> request) =>
      call({'op': 'derive', 'name': name, ...request});

  /// A single classification answer (used by the model getters and tests).
  Map<String, Object?> classify(String op, Map<String, Object?> request) =>
      call({'op': 'classify.$op', ...request});

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}

/// Runs a `derive` on a worker isolate, so an aggregate that grows with the log
/// dataset cannot stall the frame that receives it. Falls back to this isolate
/// when a worker cannot be spawned, such as a test host without the built
/// library on its path.
Future<Map<String, Object?>> deriveOffThread(
  String name,
  Map<String, Object?> request,
) async {
  try {
    return await Isolate.run(
      () => RustLogQueryCore.instance.derive(name, request),
    );
  } catch (_) {
    return RustLogQueryCore.instance.derive(name, request);
  }
}
