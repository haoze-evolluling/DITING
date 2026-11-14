/// A10 state: the local HTTP API's token and running state. The server itself lives in
/// [LocalApiServer]; this notifier only starts/stops it and holds the token the page shows.
library;

import 'dart:convert';
import 'dart:math';

import 'package:diting_android/data/network/local_api_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocalApiState {
  const LocalApiState({
    required this.token,
    required this.running,
    this.port,
    this.error,
  });

  final String token;
  final bool running;
  final int? port;
  final String? error;

  LocalApiState copyWith({
    String? token,
    bool? running,
    int? port,
    String? error,
    bool clearError = false,
  }) => LocalApiState(
    token: token ?? this.token,
    running: running ?? this.running,
    port: port ?? this.port,
    error: clearError ? null : (error ?? this.error),
  );
}

/// A 24-byte URL-safe token; enough entropy that guessing is hopeless and copy/paste stays short.
String generateLocalApiToken([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(24, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

class LocalApiNotifier extends Notifier<LocalApiState> {
  LocalApiServer? _server;

  @override
  LocalApiState build() {
    ref.onDispose(() => _server?.stop());
    return LocalApiState(token: generateLocalApiToken(), running: false);
  }

  /// Starts (or stops) the server. A stop is best-effort; a start failure lands in [LocalApiState.error].
  Future<void> setEnabled(bool enabled) async {
    if (enabled == state.running) return;
    if (!enabled) {
      await _server?.stop();
      _server = null;
      state = state.copyWith(running: false, port: null, clearError: true);
      return;
    }
    final server = LocalApiServer(token: state.token);
    try {
      final port = await server.start();
      _server = server;
      state = state.copyWith(running: true, port: port, clearError: true);
    } catch (error) {
      await server.stop();
      state = state.copyWith(running: false, clearError: true, error: '$error');
    }
  }

  /// Regenerates the token; if the server is running it restarts with the new token.
  Future<void> regenerate() async {
    final wasRunning = state.running;
    if (wasRunning) {
      await _server?.stop();
      _server = null;
    }
    final token = generateLocalApiToken();
    state = state.copyWith(token: token, running: false, port: null);
    if (wasRunning) {
      await setEnabled(true);
    }
  }
}

final localApiProvider = NotifierProvider<LocalApiNotifier, LocalApiState>(
  LocalApiNotifier.new,
);
