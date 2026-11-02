/// The DNS64 synthesizer's config, as `GET /api/v1/status` reports it under `dns64`.
///
/// The service is the only source of truth: it validates every prefix (RFC 6052 allows /32, /40,
/// /48, /56, /64 and /96 only) and answers with the list it kept. The page therefore parses what is
/// typed into lines and nothing more.
library;

/// RFC 6052's well-known prefix; the service falls back to it when the list is empty.
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

  /// The prefixes the service holds. Empty means it is using
  /// [desktopDns64WellKnownPrefix] on its own.
  final List<String> prefixes;

  List<String> get effectivePrefixes =>
      prefixes.isEmpty ? const [desktopDns64WellKnownPrefix] : prefixes;

  /// One prefix per line, the shape the console's textarea uses.
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

/// The textarea's lines, trimmed, blanks dropped. Empty stays empty: whether that means "use the
/// well-known prefix" is the service's decision, not the form's.
List<String> desktopDns64ParsePrefixes(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];
