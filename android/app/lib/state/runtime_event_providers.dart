library;

import 'package:diting_android/data/native/runtime_event.dart';
import 'package:diting_android/state/runtime_log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final runtimeEventsProvider = FutureProvider.autoDispose<List<RuntimeEvent>>((
  ref,
) async {
  final text = await ref.watch(runtimeLogBridgeProvider).readEvents(limit: 500);
  return RuntimeEvent.parseAll(text);
});
