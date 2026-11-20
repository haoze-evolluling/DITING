library;

import 'dart:async';

import 'package:diting_android/data/native/runtime_log_bridge.dart';

abstract final class RuntimeEvents {
  static final RuntimeLogBridge _bridge = RuntimeLogBridge();

  static void report(
    String module,
    String event, {
    int level = RuntimeEventLevel.info,
    Map<String, Object?> fields = const {},
  }) {
    unawaited(
      _bridge.appendEvent(
        module: module,
        event: event,
        level: level,
        fields: fields,
      ),
    );
  }

  static void startup(String stage, int elapsedMs) =>
      report('startup', stage, fields: {'ms': elapsedMs});

  static void error(String module, Object error, {StackTrace? stack}) => report(
    module,
    'error',
    level: RuntimeEventLevel.error,
    fields: {'error': '$error'},
  );
}
