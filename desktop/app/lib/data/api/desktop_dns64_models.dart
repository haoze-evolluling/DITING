library;

const String desktopDns64WellKnownPrefix = '64:ff9b::/96';

class DesktopDns64Config {
  const DesktopDns64Config({
    required this.enabled,
    required this.prefixes,
  });

  factory DesktopDns64Config.fromJson(Map<String, Object?> json) =>
      DesktopDns64Config(
        enabled: json['enabled'] == true,
        prefixes: switch (json['prefixes']) {
          List() => [
            for (final item in json['prefixes'] as List)
              if ('$item'.trim().isNotEmpty) '$item'.trim(),
          ],
          _ => const [],
        },
      );

  final bool enabled;

  final List<String> prefixes;

  List<String> get effectivePrefixes =>
      prefixes.isEmpty ? const [desktopDns64WellKnownPrefix] : prefixes;

  String get prefixText => effectivePrefixes.join('\n');

  DesktopDns64Config copyWith({bool? enabled, List<String>? prefixes}) =>
      DesktopDns64Config(
        enabled: enabled ?? this.enabled,
        prefixes: prefixes ?? this.prefixes,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'prefixes': prefixes,
  };
}

List<String> desktopDns64ParsePrefixes(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];
