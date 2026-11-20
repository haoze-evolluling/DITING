library;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

double _double(Object? value) => switch (value) {
  num() => value.toDouble(),
  String() => double.tryParse(value) ?? 0,
  _ => 0,
};

bool _bool(Object? value) => value == true;

String _string(Object? value) => value == null ? '' : '$value';

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Map<String, Object?>> _maps(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is Map) item.cast<String, Object?>(),
];

const List<String> desktopUpstreamModes = [
  'single',
  'primary_backup',
  'parallel_race',
  'smart_prediction',
];

const List<String> desktopUpstreamProtocols = [
  'PLAIN',
  'DOT',
  'DOH',
  'DOH3',
  'DOQ',
];

bool desktopIsHttpsStyle(String protocol) =>
    protocol == 'DOH' || protocol == 'DOH3';

class DesktopUpstreamProvider {
  const DesktopUpstreamProvider({
    required this.id,
    required this.protocol,
    required this.server,
    this.url = '',
    this.weight = 1,
    this.pin = '',
  });

  factory DesktopUpstreamProvider.fromJson(Map<String, Object?> json) =>
      DesktopUpstreamProvider(
        id: _string(json['id']),
        protocol: _string(json['protocol']).toUpperCase(),
        server: _string(json['server']),
        url: _string(json['url']),
        weight: _int(json['weight']),
        pin: _string(json['pin']),
      );

  final String id;
  final String protocol;

  final String server;
  final String url;
  final int weight;

  final String pin;

  String get address => url.isNotEmpty ? url : server;

  DesktopUpstreamProvider copyWith({
    String? id,
    String? protocol,
    String? server,
    String? url,
    int? weight,
    String? pin,
  }) => DesktopUpstreamProvider(
    id: id ?? this.id,
    protocol: protocol ?? this.protocol,
    server: server ?? this.server,
    url: url ?? this.url,
    weight: weight ?? this.weight,
    pin: pin ?? this.pin,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'protocol': protocol,
    'server': server,
    'url': url,
    'weight': weight,
    if (pin.isNotEmpty) 'pin': pin,
  };
}

class DesktopBootstrapServer {
  const DesktopBootstrapServer({
    required this.id,
    required this.name,
    required this.address,
    this.weight = 1,
  });

  factory DesktopBootstrapServer.fromJson(Map<String, Object?> json) =>
      DesktopBootstrapServer(
        id: _string(json['id']),
        name: _string(json['name']),
        address: _string(json['address']),
        weight: _double(json['weight']),
      );

  final String id;
  final String name;
  final String address;
  final double weight;

  DesktopBootstrapServer copyWith({
    String? id,
    String? name,
    String? address,
    double? weight,
  }) => DesktopBootstrapServer(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address ?? this.address,
    weight: weight ?? this.weight,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'weight': weight,
  };
}

class DesktopUpstreamConfig {
  const DesktopUpstreamConfig({
    required this.mode,
    required this.providers,
    required this.bootstrapEnabled,
    required this.bootstrapServers,
    required this.conditionalRoutes,
    required this.fallbackProviders,
    required this.fallbackTimeoutMs,
    required this.fallbackOnRcode,
    required this.fallbackOnError,
  });

  static const defaultFallbackTimeoutMs = 2000;
  static const defaultFallbackRcodes = [2, 5];

  factory DesktopUpstreamConfig.fromJson(Map<String, Object?> json) {
    final mode = _string(json['mode']).toLowerCase();
    final bootstrap = _map(json['bootstrap']);
    final rcode = json['fallbackOnRcode'];
    return DesktopUpstreamConfig(
      mode: desktopUpstreamModes.contains(mode) ? mode : 'primary_backup',
      providers: [
        for (final item in _maps(json['providers']))
          DesktopUpstreamProvider.fromJson(item),
      ],
      bootstrapEnabled: bootstrap['enabled'] == null
          ? true
          : _bool(bootstrap['enabled']),
      bootstrapServers: [
        for (final item in _maps(bootstrap['servers']))
          DesktopBootstrapServer.fromJson(item),
      ],
      conditionalRoutes: {
        for (final entry in _map(json['conditionalRoutes']).entries)
          entry.key: _string(entry.value),
      },
      fallbackProviders: [
        for (final item in _maps(json['fallbackProviders']))
          DesktopUpstreamProvider.fromJson(item),
      ],
      fallbackTimeoutMs: _int(json['fallbackTimeoutMs']),
      fallbackOnRcode: rcode is List
          ? [for (final value in rcode) _int(value)]
          : defaultFallbackRcodes,
      fallbackOnError: json['fallbackOnError'] == null
          ? true
          : _bool(json['fallbackOnError']),
    );
  }

  final String mode;
  final List<DesktopUpstreamProvider> providers;
  final bool bootstrapEnabled;
  final List<DesktopBootstrapServer> bootstrapServers;

  final Map<String, String> conditionalRoutes;

  final List<DesktopUpstreamProvider> fallbackProviders;

  final int fallbackTimeoutMs;
  final List<int> fallbackOnRcode;
  final bool fallbackOnError;

  bool get fallbackEnabled => fallbackProviders.isNotEmpty;

  int get effectiveFallbackTimeoutMs =>
      fallbackTimeoutMs > 0 ? fallbackTimeoutMs : defaultFallbackTimeoutMs;

  DesktopUpstreamConfig copyWith({
    String? mode,
    List<DesktopUpstreamProvider>? providers,
    bool? bootstrapEnabled,
    List<DesktopBootstrapServer>? bootstrapServers,
    Map<String, String>? conditionalRoutes,
    List<DesktopUpstreamProvider>? fallbackProviders,
    int? fallbackTimeoutMs,
    List<int>? fallbackOnRcode,
    bool? fallbackOnError,
  }) => DesktopUpstreamConfig(
    mode: mode ?? this.mode,
    providers: providers ?? this.providers,
    bootstrapEnabled: bootstrapEnabled ?? this.bootstrapEnabled,
    bootstrapServers: bootstrapServers ?? this.bootstrapServers,
    conditionalRoutes: conditionalRoutes ?? this.conditionalRoutes,
    fallbackProviders: fallbackProviders ?? this.fallbackProviders,
    fallbackTimeoutMs: fallbackTimeoutMs ?? this.fallbackTimeoutMs,
    fallbackOnRcode: fallbackOnRcode ?? this.fallbackOnRcode,
    fallbackOnError: fallbackOnError ?? this.fallbackOnError,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.toUpperCase(),
    'providers': [for (final provider in providers) provider.toJson()],
    'bootstrap': {
      'enabled': bootstrapEnabled,
      'servers': [for (final server in bootstrapServers) server.toJson()],
    },
    'conditionalRoutes': conditionalRoutes,
    'fallbackProviders': [
      for (final provider in fallbackProviders) provider.toJson(),
    ],
    'fallbackTimeoutMs': fallbackTimeoutMs,
    'fallbackOnRcode': fallbackOnRcode,
    'fallbackOnError': fallbackOnError,
  };
}

class DesktopStampResult {
  const DesktopStampResult({
    required this.protocol,
    required this.server,
    required this.url,
    required this.providerName,
    required this.pin,
    required this.protoName,
    required this.dnssec,
    required this.noLog,
  });

  factory DesktopStampResult.fromJson(Map<String, Object?> json) {
    final props = _map(json['props']);
    return DesktopStampResult(
      protocol: _string(json['protocol']).toUpperCase(),
      server: _string(json['server']),
      url: _string(json['url']),
      providerName: _string(json['providerName']),
      pin: _string(json['pin']),
      protoName: _string(json['protoName']),
      dnssec: _bool(props['dnssec']),
      noLog: _bool(props['noLog']),
    );
  }

  final String protocol;
  final String server;
  final String url;
  final String providerName;
  final String pin;
  final String protoName;
  final bool dnssec;
  final bool noLog;
}

class DesktopUpstreamProbe {
  const DesktopUpstreamProbe({this.latencyMs, this.error});

  final double? latencyMs;
  final String? error;

  bool get success => error == null && latencyMs != null;
}
