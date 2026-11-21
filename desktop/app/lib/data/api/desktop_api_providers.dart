library;

import 'dart:async';

import 'package:diting_shared/data/errors.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const desktopPrefsContainer = 'diting_desktop';

final desktopApiConfigProvider = Provider<DesktopApiConfig>((ref) {
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
  final signal = ref.watch(desktopAuthSignalProvider);
  final client = DesktopApiClient(
    config: ref.watch(desktopApiConfigProvider),
    onUnauthorized: signal.fire,
  );
  ref.onDispose(client.close);
  return client;
});

final desktopPollingEnabledProvider = Provider<bool>((ref) => true);

class DesktopSnapshot {
  const DesktopSnapshot({this.status, this.error});

  final DesktopStatus? status;
  final DesktopApiException? error;

  bool get isLoading => status == null && error == null;

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

  final DesktopApiException? error;

  bool get isBusy => pending != null;
}

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
      ignoreError();
    }
  }
}

final desktopRecentQueriesProvider =
    NotifierProvider<DesktopRecentQueriesNotifier, List<QueryLogEntry>>(
      DesktopRecentQueriesNotifier.new,
    );
