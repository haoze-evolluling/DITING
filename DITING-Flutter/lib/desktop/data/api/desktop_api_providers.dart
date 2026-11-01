/// Desktop data wiring: one client for the local service, a polled snapshot of it, and the write
/// actions the dashboard can trigger.
///
/// The service is the only source of truth; this layer never derives DNS state from what it just
/// asked for. Every action re-reads `/api/v1/status` instead of writing the expected result.
library;

import 'dart:async';

import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Container for the desktop host's own connection settings, so they cannot collide with an
/// Android preference of the same name.
const desktopPrefsContainer = 'diting_desktop';

/// Where the local service listens. Defaults to the loopback address the service binds out of the
/// box; the keys match what the Wails console writes.
final desktopApiConfigProvider = Provider<DesktopApiConfig>((ref) {
  // The browser that loaded the web console talks to the origin it came from, and authenticates with
  // the session token instead of the desktop host's IPC token.
  if (ref.watch(desktopWebConsoleProvider)) {
    final origin = ref.watch(desktopPageOriginProvider);
    return DesktopApiConfig(
      scheme: origin.scheme,
      host: origin.host,
      port: origin.port,
      token: ref.watch(desktopSessionTokenProvider),
    );
  }
  final store = ref.watch(legacyPrefsStoreProvider);
  final host = store.read(desktopPrefsContainer, 'ipc_host');
  final port = store.read(desktopPrefsContainer, 'ipc_port');
  final token = store.read(desktopPrefsContainer, 'ipc_token');
  return DesktopApiConfig(
    host: host is String && host.isNotEmpty ? host : '127.0.0.1',
    port: switch (port) {
      final int value => value,
      final String value => int.tryParse(value) ?? 15353,
      _ => 15353,
    },
    token: token is String ? token : '',
  );
});

final desktopApiClientProvider = Provider<DesktopApiClient>((ref) {
  // A 401 on a request that carried a token means the web session expired; the signal carries that
  // news to the auth state machine without the client depending on it.
  final signal = ref.watch(desktopAuthSignalProvider);
  final client = DesktopApiClient(
    config: ref.watch(desktopApiConfigProvider),
    onUnauthorized: signal.fire,
  );
  ref.onDispose(client.close);
  return client;
});

/// Whether the snapshot polls on its own timer. Widget tests turn it off, because a pending
/// periodic timer fails the test as soon as it ends.
final desktopPollingEnabledProvider = Provider<bool>((ref) => true);

/// One poll result. [status] survives a failed poll on purpose: a dashboard that showed real
/// figures a second ago is better off showing them marked stale than showing nothing.
class DesktopSnapshot {
  const DesktopSnapshot({this.status, this.error});

  final DesktopStatus? status;
  final DesktopApiException? error;

  bool get isLoading => status == null && error == null;

  /// Values on screen, but the service is not answering any more.
  bool get isStale => status != null && error != null;
}

class DesktopStatusNotifier extends Notifier<DesktopSnapshot> {
  static const pollInterval = Duration(seconds: 2);

  Timer? _timer;

  @override
  DesktopSnapshot build() {
    final client = ref.watch(desktopApiClientProvider);
    _timer?.cancel();
    _timer = null;
    if (ref.watch(desktopPollingEnabledProvider)) {
      _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
      ref.onDispose(() => _timer?.cancel());
    }
    unawaited(_load(client));
    return const DesktopSnapshot();
  }

  Future<void> refresh() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final status = await client.status();
      if (ref.mounted) state = DesktopSnapshot(status: status);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopSnapshot(status: state.status, error: error);
      }
    }
  }
}

final desktopStatusProvider =
    NotifierProvider<DesktopStatusNotifier, DesktopSnapshot>(
      DesktopStatusNotifier.new,
    );

/// Host service state, which changes far less often than the DNS snapshot.
class DesktopServiceStatusNotifier extends Notifier<CoreServiceState?> {
  static const pollInterval = Duration(seconds: 10);

  Timer? _timer;

  @override
  CoreServiceState? build() {
    final client = ref.watch(desktopApiClientProvider);
    _timer?.cancel();
    _timer = null;
    if (ref.watch(desktopPollingEnabledProvider)) {
      _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
      ref.onDispose(() => _timer?.cancel());
    }
    unawaited(_load(client));
    return null;
  }

  Future<void> refresh() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final service = await client.serviceStatus();
      if (ref.mounted) state = service;
    } on DesktopApiException {
      // The card says "unknown" by staying null; a service that cannot report its own state is not
      // an error worth a second banner over the dashboard's own.
      if (ref.mounted) state = null;
    }
  }
}

final desktopServiceStatusProvider =
    NotifierProvider<DesktopServiceStatusNotifier, CoreServiceState?>(
      DesktopServiceStatusNotifier.new,
    );

enum DesktopControlAction { startDns, stopDns, takeover, filter }

class DesktopControlState {
  const DesktopControlState({this.pending, this.error});

  final DesktopControlAction? pending;

  /// Last failure, cleared by the next successful action. The UI turns it into a message.
  final DesktopApiException? error;

  bool get isBusy => pending != null;
}

/// The write paths the dashboard owns. Each one is guarded against overlapping requests: the
/// service arbitrates concurrent lifecycle commands, so a second one from a double tap only
/// muddies what the UI then shows.
class DesktopControlNotifier extends Notifier<DesktopControlState> {
  @override
  DesktopControlState build() => const DesktopControlState();

  Future<void> toggleDns() {
    final running = ref.read(desktopStatusProvider).status?.dns.running;
    return running == true ? stopDns() : startDns();
  }

  Future<void> startDns() =>
      _run(DesktopControlAction.startDns, (client) => client.startDns());

  Future<void> stopDns() =>
      _run(DesktopControlAction.stopDns, (client) => client.stopDns());

  Future<void> setTakeover(bool enabled) => _run(
    DesktopControlAction.takeover,
    (client) => client.setTakeover(enabled),
  );

  Future<void> setFilterPaused(bool paused) => _run(
    DesktopControlAction.filter,
    (client) => client.setFilterPaused(paused),
  );

  Future<void> _run(
    DesktopControlAction action,
    Future<void> Function(DesktopApiClient client) body,
  ) async {
    if (state.isBusy) return;
    state = DesktopControlState(pending: action);
    try {
      await body(ref.read(desktopApiClientProvider));
      await ref.read(desktopStatusProvider.notifier).refresh();
      if (ref.mounted) state = const DesktopControlState();
    } on DesktopApiException catch (error) {
      if (ref.mounted) state = DesktopControlState(error: error);
    }
  }

  void clearError() {
    if (state.error == null) return;
    state = DesktopControlState(pending: state.pending);
  }
}

final desktopControlProvider =
    NotifierProvider<DesktopControlNotifier, DesktopControlState>(
      DesktopControlNotifier.new,
    );

/// The last few queries, newest first. Separate from the status snapshot because the log is a
/// different endpoint with a different cost, and a log outage must not blank the dashboard.
class DesktopRecentQueriesNotifier extends Notifier<List<QueryLogEntry>> {
  static const pollInterval = Duration(seconds: 5);

  Timer? _timer;

  @override
  List<QueryLogEntry> build() {
    final client = ref.watch(desktopApiClientProvider);
    _timer?.cancel();
    _timer = null;
    if (ref.watch(desktopPollingEnabledProvider)) {
      _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
      ref.onDispose(() => _timer?.cancel());
    }
    unawaited(_load(client));
    return const [];
  }

  Future<void> refresh() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final page = await client.recentQueries();
      if (ref.mounted) state = page.entries;
    } on DesktopApiException {
      // Keep the last page: the table says "no queries" only when the service said so.
    }
  }
}

final desktopRecentQueriesProvider =
    NotifierProvider<DesktopRecentQueriesNotifier, List<QueryLogEntry>>(
      DesktopRecentQueriesNotifier.new,
    );
