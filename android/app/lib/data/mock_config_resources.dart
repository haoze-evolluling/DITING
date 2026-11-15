/// Kept-resource demo data. Initial values only; mutable copies live in
/// `lib/state/config_providers_resources.dart`.
library;

class MockUserAgent {
  const MockUserAgent({
    required this.value,
    this.name = '',
    this.isDefault = false,
  });

  /// The actual User-Agent string sent on the wire.
  final String value;

  /// The user-facing label shown on the card. Empty for rows saved before names
  /// existed; [displayName] then falls back to [value] so nothing breaks.
  final String name;

  /// Built-in presets can be selected but not removed or renamed.
  final bool isDefault;

  /// What the card shows: the name, not the raw UA string.
  String get displayName => name.trim().isEmpty ? value : name;
}

const mockUserAgents = <MockUserAgent>[
  // Built-in presets: common browsers, kept for bypassing UA-sniffing servers.
  // Built-ins cannot be deleted; the core falls back to its own UA otherwise.
  MockUserAgent(
    name: 'Chrome / Android',
    value:
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Mobile Safari/537.36',
    isDefault: true,
  ),
  MockUserAgent(
    name: 'Safari / iPhone',
    value:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
        'Mobile/15E148 Safari/604.1',
    isDefault: true,
  ),
  MockUserAgent(
    name: 'Edge / Windows',
    value:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0',
    isDefault: true,
  ),
  MockUserAgent(
    name: 'Firefox / Windows',
    value:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) '
        'Gecko/20100101 Firefox/127.0',
    isDefault: true,
  ),
  // Editable examples of user-added agents.
  MockUserAgent(
    name: 'Chrome / Windows',
    value:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Safari/537.36',
  ),
  MockUserAgent(
    name: 'Safari / macOS',
    value:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
  ),
  MockUserAgent(name: 'curl', value: 'curl/8.7.1'),
];

class MockSsidRule {
  const MockSsidRule({
    required this.ssid,
    this.cellular = true,
    this.wifi = true,
    this.delayMs = 0,
  });

  final String ssid;
  final bool cellular;
  final bool wifi;

  final int delayMs;

  MockSsidRule copyWith({bool? cellular, bool? wifi, int? delayMs}) =>
      MockSsidRule(
        ssid: ssid,
        cellular: cellular ?? this.cellular,
        wifi: wifi ?? this.wifi,
        delayMs: delayMs ?? this.delayMs,
      );

  bool get enabled => cellular || wifi;
}

const mockSsidRules = <MockSsidRule>[
  MockSsidRule(ssid: 'Home-5G', cellular: false, delayMs: 800),
  MockSsidRule(ssid: 'Office-WiFi', cellular: true, wifi: true),
  MockSsidRule(ssid: 'Starbucks', cellular: true, wifi: false, delayMs: 1500),
];
