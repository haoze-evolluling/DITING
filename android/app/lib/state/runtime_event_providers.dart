/// Page state for the 故障排查 → 运行事件 timeline. The native black box owns the file; this only
/// reads the tail and parses it for filtering.
library;

import 'package:diting_android/data/native/runtime_event.dart';
import 'package:diting_android/state/runtime_log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The most recent structured events, newest last.
final runtimeEventsProvider = FutureProvider.autoDispose<List<RuntimeEvent>>((
  ref,
) async {
  final text = await ref.watch(runtimeLogBridgeProvider).readEvents(limit: 500);
  return RuntimeEvent.parseAll(text);
});
