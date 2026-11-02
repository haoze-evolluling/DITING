/// The web console's session: whether an admin exists, whether this browser holds a valid token, and
/// the login background the login page renders.
///
/// The desktop window never uses any of this: it reaches the service over loopback IPC with the
/// configured `ipc_token`, so [desktopWebConsoleProvider] is false and the gate steps aside. The
/// browser that loaded the same bundle from the LAN console is the case this file exists for.
library;

import 'dart:async';

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_auth_models.dart';
import 'package:diting_desktop/data/host/desktop_platform_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Container for the browser session, kept apart from the desktop host's IPC keys.
const desktopSessionTokenKey = 'session_token';
const desktopSessionUserKey = 'session_user';

/// The origin the bundle was loaded from: the API base and the base of the background image URL.
final desktopPageOriginProvider = Provider<Uri>(
  (ref) => desktopPageOrigin ?? Uri.base,
);

/// True when the bundle is being served to a browser, i.e. the LAN web console. Wails injects its
/// bindings into the desktop window, so `window.go` tells the two apart.
final desktopWebConsoleProvider = Provider<bool>(
  (ref) => kIsWeb && !desktopHasWailsBindings,
);

/// Fires when the service answers 401 to a request that carried a session token. A plain object
/// rather than a provider state, so the API client can signal without depending on the auth state
/// that depends on the client.
class DesktopAuthSignal {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void fire() {
    if (!_controller.isClosed) _controller.add(null);
  }

  void dispose() => _controller.close();
}

final desktopAuthSignalProvider = Provider<DesktopAuthSignal>((ref) {
  final signal = DesktopAuthSignal();
  ref.onDispose(signal.dispose);
  return signal;
});

/// The session token this browser holds. Empty in the desktop window, where the IPC token is used
/// instead. Changing it rebuilds the API client, so every page re-reads with the new credential.
class DesktopSessionTokenNotifier extends Notifier<String> {
  @override
  String build() {
    if (!ref.watch(desktopWebConsoleProvider)) return '';
    final token = ref
        .watch(legacyPrefsStoreProvider)
        .read(desktopPrefsContainer, desktopSessionTokenKey);
    return token is String ? token : '';
  }

  void save(String token, {String username = ''}) {
    final store = ref.read(legacyPrefsStoreProvider);
    store.putString(desktopPrefsContainer, desktopSessionTokenKey, token);
    if (username.isNotEmpty) {
      store.putString(desktopPrefsContainer, desktopSessionUserKey, username);
    }
    state = token;
  }

  void clear() {
    final store = ref.read(legacyPrefsStoreProvider);
    store.remove(desktopPrefsContainer, desktopSessionTokenKey);
    store.remove(desktopPrefsContainer, desktopSessionUserKey);
    state = '';
  }
}

final desktopSessionTokenProvider =
    NotifierProvider<DesktopSessionTokenNotifier, String>(
      DesktopSessionTokenNotifier.new,
    );

enum DesktopAuthPhase {
  /// The first `/auth/status` read is in flight.
  checking,

  /// No usable session: the login (or setup) page is shown.
  signedOut,

  /// The token was accepted by a protected route.
  signedIn,

  /// The service itself could not be reached; the gate offers a retry instead of a login form.
  unreachable,
}

class DesktopAuthState {
  const DesktopAuthState({
    this.phase = DesktopAuthPhase.checking,
    this.initialized = false,
    this.username = '',
    this.lockoutRemaining = Duration.zero,
    this.error,
  });

  final DesktopAuthPhase phase;

  /// Whether an admin password exists; before that the console asks for one instead of logging in.
  final bool initialized;
  final String username;
  final Duration lockoutRemaining;

  /// Only set for [DesktopAuthPhase.unreachable]; a rejected credential is the form's own error.
  final DesktopApiException? error;

  bool get checking => phase == DesktopAuthPhase.checking;
  bool get signedIn => phase == DesktopAuthPhase.signedIn;
  bool get unreachable => phase == DesktopAuthPhase.unreachable;
}

class DesktopAuthNotifier extends Notifier<DesktopAuthState> {
  @override
  DesktopAuthState build() {
    // Read, not watch: a new client (from a token change) must not restart the state machine, or the
    // screen would drop back to "checking" right after a successful login.
    final signal = ref.watch(desktopAuthSignalProvider);
    final subscription = signal.stream.listen((_) => _expire());
    ref.onDispose(subscription.cancel);
    unawaited(_check());
    return const DesktopAuthState();
  }

  DesktopApiClient get _client => ref.read(desktopApiClientProvider);

  DesktopSessionTokenNotifier get _session =>
      ref.read(desktopSessionTokenProvider.notifier);

  Future<void> retry() => _check();

  Future<void> _check() async {
    if (!ref.read(desktopWebConsoleProvider)) return;
    state = const DesktopAuthState();
    try {
      final status = await _client.authStatus();
      final token = ref.read(desktopSessionTokenProvider);
      if (!status.initialized) {
        state = DesktopAuthState(
          phase: DesktopAuthPhase.signedOut,
          username: status.username,
        );
        return;
      }
      if (token.isEmpty) {
        state = DesktopAuthState(
          phase: DesktopAuthPhase.signedOut,
          initialized: true,
          username: status.username,
          lockoutRemaining: status.lockoutRemaining,
        );
        return;
      }
      try {
        // The only way to know a stored token is still valid: ask a protected route.
        await _client.status();
        state = DesktopAuthState(
          phase: DesktopAuthPhase.signedIn,
          initialized: true,
          username: status.username,
        );
      } on DesktopApiException catch (error) {
        if (!error.unauthorized) rethrow;
        _session.clear();
        state = DesktopAuthState(
          phase: DesktopAuthPhase.signedOut,
          initialized: true,
          username: status.username,
        );
      }
    } on DesktopApiException catch (error) {
      state = DesktopAuthState(
        phase: DesktopAuthPhase.unreachable,
        error: error,
      );
    }
  }

  Future<DesktopApiException?> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final session = await _client.signIn(
        username: username,
        password: password,
      );
      final name = session.username.isEmpty ? username : session.username;
      _session.save(session.token, username: name);
      state = DesktopAuthState(
        phase: DesktopAuthPhase.signedIn,
        initialized: true,
        username: name,
      );
      return null;
    } on DesktopApiException catch (error) {
      await _refreshFailure();
      return error;
    }
  }

  /// First-run setup: the service stores the credential, then the same session is opened.
  Future<DesktopApiException?> setUp({
    required String username,
    required String password,
  }) async {
    try {
      await _client.setupAdmin(username: username, password: password);
    } on DesktopApiException catch (error) {
      await _refreshFailure();
      return error;
    }
    return signIn(username: username, password: password);
  }

  /// Rotating the credential from the login page: the service invalidates every other session, so
  /// the caller returns to the login form instead of assuming it is still signed in.
  Future<DesktopApiException?> changePassword({
    required String username,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _client.changeAdminPassword(
        username: username,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      return null;
    } on DesktopApiException catch (error) {
      return error;
    }
  }

  Future<DesktopApiException?> signOut() async {
    DesktopApiException? failure;
    try {
      await _client.signOut();
    } on DesktopApiException catch (error) {
      failure = error;
    }
    _session.clear();
    state = DesktopAuthState(
      phase: DesktopAuthPhase.signedOut,
      initialized: state.initialized,
      username: state.username,
    );
    return failure;
  }

  /// A 401 from a page: the session is gone, so drop the token and ask for credentials again.
  void _expire() {
    if (!ref.read(desktopWebConsoleProvider)) return;
    if (state.phase != DesktopAuthPhase.signedIn) return;
    _session.clear();
    state = DesktopAuthState(
      phase: DesktopAuthPhase.signedOut,
      initialized: state.initialized,
      username: state.username,
    );
  }

  /// After a rejected credential the service's own status is the truth about which case it was.
  Future<void> _refreshFailure() async {
    try {
      final status = await _client.authStatus();
      state = DesktopAuthState(
        phase: DesktopAuthPhase.signedOut,
        initialized: status.initialized,
        username: status.username,
        lockoutRemaining: status.lockoutRemaining,
      );
    } on DesktopApiException {
      state = DesktopAuthState(
        phase: DesktopAuthPhase.signedOut,
        initialized: state.initialized,
        username: state.username,
      );
    }
  }
}

final desktopAuthProvider =
    NotifierProvider<DesktopAuthNotifier, DesktopAuthState>(
      DesktopAuthNotifier.new,
    );

/// The login page's background, as the service reports it. Loaded on demand, because only the login
/// page renders it.
class DesktopLoginBackgroundNotifier extends Notifier<DesktopLoginBackground?> {
  @override
  DesktopLoginBackground? build() => null;

  Future<void> load() async {
    try {
      final background = await ref
          .read(desktopApiClientProvider)
          .loginBackground();
      if (ref.mounted) state = background;
    } on DesktopApiException {
      // The login form still works without a wallpaper; nothing to report here.
    }
  }

  Future<DesktopApiException?> save({
    required String url,
    required int opacity,
    required int blur,
    String adminPassword = '',
  }) => _write(() async {
    final background = await ref
        .read(desktopApiClientProvider)
        .setLoginBackground(
          url: url,
          opacity: opacity,
          blur: blur,
          adminPassword: adminPassword,
        );
    if (ref.mounted) state = background;
  });

  Future<DesktopApiException?> reset({String adminPassword = ''}) =>
      _write(() async {
        final background = await ref
            .read(desktopApiClientProvider)
            .resetLoginBackground(adminPassword: adminPassword);
        if (ref.mounted) state = background;
      });

  Future<DesktopApiException?> _write(Future<void> Function() write) async {
    try {
      await write();
      return null;
    } on DesktopApiException catch (error) {
      return error;
    }
  }
}

final desktopLoginBackgroundProvider =
    NotifierProvider<
      DesktopLoginBackgroundNotifier,
      DesktopLoginBackground?
    >(DesktopLoginBackgroundNotifier.new);
