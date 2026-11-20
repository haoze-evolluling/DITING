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
