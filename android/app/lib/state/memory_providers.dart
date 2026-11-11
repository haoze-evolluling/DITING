/// Live memory sampling shaped like [speedSeriesProvider]; 2 s period, since it crosses Binder into
/// `ActivityManager`.
library;

import 'dart:async';

import 'package:diting_shared/data/native/process_memory.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_shared/ui/scroll_activity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const memoryPollInterval = Duration(seconds: 2);

final processMemoryProvider =
    NotifierProvider<ProcessMemoryNotifier, ProcessMemory>(
      ProcessMemoryNotifier.new,
    );

class ProcessMemoryNotifier extends Notifier<ProcessMemory> {
  Timer? _timer;
  int _attachments = 0;
  bool _inFlight = false;
  bool _queuedForIdle = false;

  @override
  ProcessMemory build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _attachments = 0;
    });
    return const ProcessMemory();
  }

  void attachPolling() {
    _attachments++;
    if (debugDisableDashboardLiveUpdates || _timer != null) return;
    _timer = Timer.periodic(memoryPollInterval, (_) => tick());
    unawaited(tick());
  }

  void detachPolling() {
    if (_attachments > 0) _attachments--;
    if (_attachments > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  /// Samples memory once; without the channel the snapshot is unavailable and the card shows a
  /// dash.
  Future<void> tick() async {
    // The figure repaints its card; sample after the fling instead of inside it.
    if (ScrollActivityGate.isScrolling) {
      if (!_queuedForIdle) {
        _queuedForIdle = true;
        ScrollActivityGate.whenIdle(() {
          _queuedForIdle = false;
          if (ref.mounted && _attachments > 0) unawaited(tick());
        });
      }
      return;
    }
    if (_inFlight) return;
    _inFlight = true;
    ProcessMemory next;
    try {
      next = await ref.read(platformBridgeProvider).memoryInfo();
    } catch (_) {
      next = const ProcessMemory();
    } finally {
      _inFlight = false;
    }
    if (!ref.mounted) return;
    // The card is a full-width tile with a shadow; re-emitting an identical snapshot repainted it
    // for nothing. PSS moves in 4 KB steps, so most 2 s ticks used to be no-ops that still drew.
    if (state == next) return;
    state = next;
  }
}
