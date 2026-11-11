/// Log-write health for 故障排查: the native writers count what they had to drop, this exposes it.
library;

import 'package:diting_android/data/native/db_health_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dbHealthBridgeProvider = Provider<DbHealthBridge>(
  (ref) => DbHealthBridge(),
);

class DbWriteHealthNotifier extends AsyncNotifier<DbWriteHealthSnapshot> {
  @override
  Future<DbWriteHealthSnapshot> build() =>
      ref.watch(dbHealthBridgeProvider).status();

  /// Re-reads the native counters; called on page open and on resume.
  Future<DbWriteHealthSnapshot> refresh() async {
    final next = await ref.read(dbHealthBridgeProvider).status();
    if (ref.mounted) state = AsyncData(next);
    return next;
  }
}

final dbWriteHealthProvider =
    AsyncNotifierProvider<DbWriteHealthNotifier, DbWriteHealthSnapshot>(
      DbWriteHealthNotifier.new,
    );
