/// Manual runtime-log capture state, shared by 数据与维护 → 故障排查. The native side owns the
/// files; this layer only mirrors what it reports so the switch never shows a stale state.
library;

import 'package:diting_android/data/native/runtime_log_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final runtimeLogBridgeProvider = Provider<RuntimeLogBridge>(
  (ref) => RuntimeLogBridge(),
);

class RuntimeLogStatusNotifier extends AsyncNotifier<RuntimeLogStatus> {
  @override
  Future<RuntimeLogStatus> build() =>
      ref.watch(runtimeLogBridgeProvider).status();

  /// Re-reads the native status; also used after start/stop and on resume.
  Future<RuntimeLogStatus> refresh() async {
    final next = await ref.read(runtimeLogBridgeProvider).status();
    if (ref.mounted) state = AsyncData(next);
    return next;
  }

  /// True when capture really started. A refused start leaves the previous state untouched.
  Future<bool> start() async {
    final started = await ref.read(runtimeLogBridgeProvider).start();
    await refresh();
    return started;
  }

  Future<void> stop() async {
    await ref.read(runtimeLogBridgeProvider).stop();
    await refresh();
  }
}

final runtimeLogStatusProvider =
    AsyncNotifierProvider<RuntimeLogStatusNotifier, RuntimeLogStatus>(
      RuntimeLogStatusNotifier.new,
    );
