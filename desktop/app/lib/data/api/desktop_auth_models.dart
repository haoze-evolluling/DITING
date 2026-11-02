/// The web console's credential state, one session, and the login background it renders.
///
/// The old desktop console's `views/LoginView.vue` plus `composables/useAuthForm.ts` are the
/// blueprint. The service decides whether an admin exists, whether a login is locked out and how long
/// a session lives; the page only shows those answers.
library;

bool _bool(Object? value) => value == true;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

/// `GET /api/v1/auth/status` (public).
class DesktopAuthStatus {
  const DesktopAuthStatus({
    required this.initialized,
    required this.webEnabled,
    required this.authenticated,
    required this.username,
    required this.locked,
    required this.lockoutRemaining,
  });

  factory DesktopAuthStatus.fromJson(Map<String, Object?> json) =>
      DesktopAuthStatus(
        initialized: _bool(json['initialized']),
        webEnabled: _bool(json['webEnabled']),
        authenticated: _bool(json['authenticated']),
        username: '${json['username'] ?? ''}',
        locked: _bool(json['locked']),
        lockoutRemaining: Duration(
          seconds: _int(json['lockoutRemainingSec']),
        ),
      );

  /// Whether an admin password has been set; before that the console opens in setup mode.
  final bool initialized;
  final bool webEnabled;

  /// The service always answers `false` here; a session is proven by calling a protected route.
  final bool authenticated;
  final String username;
  final bool locked;
  final Duration lockoutRemaining;
}

/// `POST /api/v1/auth/login`.
class DesktopSession {
  const DesktopSession({
    required this.token,
    required this.username,
    required this.expiresAt,
  });

  factory DesktopSession.fromJson(Map<String, Object?> json) => DesktopSession(
    token: '${json['token'] ?? ''}',
    username: '${json['username'] ?? ''}',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      _int(json['expiresAt']) * 1000,
    ),
  );

  final String token;
  final String username;
  final DateTime expiresAt;
}

/// `GET|POST|DELETE /api/v1/auth/background`.
class DesktopLoginBackground {
  const DesktopLoginBackground({
    required this.type,
    required this.url,
    required this.opacity,
    required this.blur,
    required this.updatedAt,
  });

  factory DesktopLoginBackground.fromJson(Map<String, Object?> json) =>
      DesktopLoginBackground(
        type: '${json['type'] ?? 'none'}',
        url: '${json['url'] ?? ''}',
        opacity: _int(json['opacity']),
        blur: _int(json['blur']),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          _int(json['updatedAt']) * 1000,
        ),
      );

  /// `none`, `url` (an external image) or `custom` (the image the service stores).
  final String type;

  /// Absolute URL, or a service-relative path for `custom`; empty when there is no image.
  final String url;

  /// Dark overlay strength, 0–100.
  final int opacity;

  /// Blur radius in CSS pixels, 0–20.
  final int blur;
  final DateTime updatedAt;

  bool get hasImage => type != 'none' && url.isNotEmpty;
}
