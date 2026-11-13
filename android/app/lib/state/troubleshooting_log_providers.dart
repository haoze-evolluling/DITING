/// Page state for 故障排查 → 日志管理. Native owns the files; this only mirrors the listing so a
/// delete or a fresh capture is reflected after [TroubleshootingLogsNotifier.refresh].
library;

import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final troubleshootingLogBridgeProvider = Provider<TroubleshootingLogBridge>(
  (ref) => TroubleshootingLogBridge(),
);

class TroubleshootingLogsNotifier
    extends AsyncNotifier<List<TroubleshootLogEntry>> {
  @override
  Future<List<TroubleshootLogEntry>> build() =>
      ref.watch(troubleshootingLogBridgeProvider).list();

  Future<List<TroubleshootLogEntry>> refresh() async {
    final next = await ref.read(troubleshootingLogBridgeProvider).list();
    if (ref.mounted) state = AsyncData(next);
    return next;
  }
}

final troubleshootingLogsProvider =
    AsyncNotifierProvider<
      TroubleshootingLogsNotifier,
      List<TroubleshootLogEntry>
    >(TroubleshootingLogsNotifier.new);
