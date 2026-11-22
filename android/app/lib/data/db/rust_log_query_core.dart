library;

import 'dart:isolate';

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31514C44;

class LogQueryPlan {
  const LogQueryPlan(this.sql, this.args);

  final String sql;
  final List<Object?> args;
}

class RustLogQueryCore {
  RustLogQueryCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustLogQueryCore? _instance;

  static RustLogQueryCore get instance => _instance ??= _load();

  static RustLogQueryCore _load() => RustLogQueryCore._(
    KernelCore.load(
      crate: 'diting-log-query-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'log query core',
    ),
  );

  LogQueryPlan plan(String name, [Map<String, Object?> params = const {}]) {
    final answer = call({'op': 'plan', 'name': name, ...params});
    return LogQueryPlan(
      answer['sql']! as String,
      List<Object?>.from(answer['args'] as List? ?? const []),
    );
  }

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

  Map<String, Object?> derive(String name, Map<String, Object?> request) =>
      call({'op': 'derive', 'name': name, ...request});

  Map<String, Object?> classify(String op, Map<String, Object?> request) =>
      call({'op': 'classify.$op', ...request});

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}

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
