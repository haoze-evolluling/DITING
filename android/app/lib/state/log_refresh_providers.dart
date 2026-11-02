/// Periodic re-query of the log-derived dashboard data.
///
/// The native side keeps writing `dns_log`, `dns_cache` and `bootstrap_log` while the tunnel
/// runs, but every log provider only rebuilds when [dnsLogRevisionProvider] is bumped, which
/// previously happened on manual refresh only. Without a timer the home cards keep whatever the
/// first query returned, so freshly written cache and bootstrap rows never appear.
library;

import 'dart:async';

import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 10 s: matches the native cache mirror's publish period, and keeps the aggregate re-query
/// (several SQLite scans per tick) off the 1 s speed timer.
const logLiveRefreshInterval = Duration(seconds: 10);

final logLiveRefreshProvider = NotifierProvider<LogLiveRefreshNotifier, int>(
  LogLiveRefreshNotifier.new,
);

/// Reference-counted like `ProcessMemoryNotifier.attachPolling`: home and the logs page can be
/// mounted at once and must share one timer.
class LogLiveRefreshNotifier extends Notifier<int> {
  Timer? _timer;
  int _attachments = 0;

  @override
  int build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _attachments = 0;
    });
    return 0;
  }

  /// Pairs with [detachPolling]; no-op under tests, where a periodic rebuild would stop
  /// `pumpAndSettle`.
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

  /// Bumps the shared revision; every log table re-queries, so the dashboard and the drill-down
  /// pages never disagree.
  void tick() {
    if (!ref.mounted) return;
    ref.read(dnsLogRevisionProvider.notifier).bump();
  }
}
