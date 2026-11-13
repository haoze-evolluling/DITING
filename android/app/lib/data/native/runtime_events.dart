/// Dart-side facade over the always-on runtime-event black box.
///
/// Startup milestones and caught/uncaught Dart errors call [RuntimeEvents], which forwards to the
/// Kotlin `RuntimeEventLog` over the `runtime_log` channel. Reporting is fire-and-forget and never
/// throws: diagnostics must not change the behaviour they are meant to observe.
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

  /// One startup milestone and the time since the previous one.
  static void startup(String stage, int elapsedMs) =>
      report('startup', stage, fields: {'ms': elapsedMs});

  static void error(String module, Object error, {StackTrace? stack}) => report(
    module,
    'error',
    level: RuntimeEventLevel.error,
    fields: {'error': '$error'},
  );
}
