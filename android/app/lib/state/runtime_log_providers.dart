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

  Future<RuntimeLogStatus> refresh() async {
    final next = await ref.read(runtimeLogBridgeProvider).status();
    if (ref.mounted) state = AsyncData(next);
    return next;
  }

  Future<bool> start() async {
    final detailed = state.value?.detailed ?? false;
    final started = await ref
        .read(runtimeLogBridgeProvider)
        .start(detailed: detailed);
    await refresh();
    return started;
  }

  Future<void> stop() async {
    await ref.read(runtimeLogBridgeProvider).stop();
    await refresh();
  }

  Future<void> setMode(bool detailed) async {
    final next = await ref
        .read(runtimeLogBridgeProvider)
        .setMode(detailed: detailed);
    if (ref.mounted) state = AsyncData(next);
  }
}

final runtimeLogStatusProvider =
    AsyncNotifierProvider<RuntimeLogStatusNotifier, RuntimeLogStatus>(
      RuntimeLogStatusNotifier.new,
    );
