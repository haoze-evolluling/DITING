library;

bool _bool(Object? value) => value == true;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

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

  final bool initialized;
  final bool webEnabled;

  final bool authenticated;
  final String username;
  final bool locked;
  final Duration lockoutRemaining;
}

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

  final String type;

  final String url;

  final int opacity;

  final int blur;
  final DateTime updatedAt;

  bool get hasImage => type != 'none' && url.isNotEmpty;
}
