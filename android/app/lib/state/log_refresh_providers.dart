library;

import 'dart:async';

import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/ui/scroll_activity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const logLiveRefreshInterval = Duration(seconds: 10);

final logLiveRefreshProvider = NotifierProvider<LogLiveRefreshNotifier, int>(
  LogLiveRefreshNotifier.new,
);

class LogLiveRefreshNotifier extends Notifier<int> {
  Timer? _timer;
  int _attachments = 0;
  bool _queuedForIdle = false;

  @override
  int build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _attachments = 0;
    });
    return 0;
  }

  void attachPolling() {
    _attachments++;
    if (debugDisableDashboardLiveUpdates || _timer != null) return;
    _timer = Timer.periodic(logLiveRefreshInterval, (_) => tick());
  }

  void detachPolling() {
    if (_attachments > 0) _attachments--;
    if (_attachments > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  void tick() {
    if (!ref.mounted) return;
    if (ScrollActivityGate.isScrolling) {
      if (!_queuedForIdle) {
        _queuedForIdle = true;
        ScrollActivityGate.whenIdle(() {
          _queuedForIdle = false;
          if (ref.mounted && _attachments > 0) tick();
        });
      }
      return;
    }
    ref.read(dnsLogRevisionProvider.notifier).bump();
  }
}
