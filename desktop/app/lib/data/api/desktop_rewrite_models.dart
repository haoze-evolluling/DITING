/// Models for custom DNS rewrite (`/api/v1/dns/rewrite/*`).
///
/// The old desktop console's `RewritePanel.vue` and `RewriteEditModal.vue` are the blueprint: the
/// same rule fields, the same record types and response codes, the same split between the shortcut
/// fields (addresses / alias / text) and the explicit record list. Every parser tolerates a missing
/// field, because the service answers `omitempty` and an older build must not blank the page.
library;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

bool _bool(Object? value) => value == true;

String _string(Object? value) => value == null ? '' : '$value';

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

/// The record types the service accepts, in its own order (`rewriteRecordTypes`).
const List<String> desktopRewriteRecordTypes = [
  'A',
  'AAAA',
  'CNAME',
  'TXT',
  'MX',
  'SRV',
  'NS',
  'PTR',
  'HTTPS',
  'SVCB',
];

/// The response codes a rule may return instead of records (`REWRITE_RCODES`).
const List<String> desktopRewriteRcodes = [
  'NOERROR',
  'FORMERR',
  'SERVFAIL',
  'NXDOMAIN',
  'NOTIMP',
  'REFUSED',
];

/// The service's default lifetime when neither the rule nor the engine sets one.
const int desktopRewriteDefaultTtl = 60;

/// The chip label the shortcut address fields carry, so the table can name it once.
const String desktopRewriteAddressChip = 'A / AAAA';

/// One explicit record (`core.RewriteRecord`): a type and its `$dnsrewrite` style value.
class DesktopRewriteRecord {
  const DesktopRewriteRecord({required this.type, required this.value});

  factory DesktopRewriteRecord.fromJson(Map<String, Object?> json) =>
      DesktopRewriteRecord(
        type: _string(json['type']).toUpperCase(),
        value: _string(json['value']),
      );

  final String type;
  final String value;

  Map<String, Object?> toJson() => {'type': type, 'value': value};
}

/// One `core.RewriteRule`. The shortcut fields and [records] are submitted together, exactly like
/// the console: switching the editor back to shortcuts must not silently drop the record list.
class DesktopRewriteRule {
  const DesktopRewriteRule({
    required this.domain,
    this.ips = const [],
    this.cname = '',
    this.txt = const [],
    this.records = const [],
    this.rcode = '',
    this.ttl = 0,
  });

  factory DesktopRewriteRule.fromJson(Map<String, Object?> json) =>
      DesktopRewriteRule(
        domain: _string(json['domain']),
        ips: _strings(json['ips']),
        cname: _string(json['cname']),
        txt: _strings(json['txt']),
        records: [
          for (final item in json['records'] as List? ?? const [])
            if (item is Map)
              DesktopRewriteRecord.fromJson(item.cast<String, Object?>()),
        ],
        rcode: _string(json['rcode']).toUpperCase(),
        ttl: _int(json['ttl']),
      );

  /// The matched name; a wildcard (`*.lan`) is matched by the service, not here.
  final String domain;
  final List<String> ips;
  final String cname;
  final List<String> txt;
  final List<DesktopRewriteRecord> records;

  /// Empty or `NOERROR` means "answer normally"; any other code means "answer with that failure and
  /// no records at all".
  final String rcode;

  /// Zero means "use the engine's default TTL".
  final int ttl;

  bool get isRcodeFailure => rcode.isNotEmpty && rcode != 'NOERROR';

  bool get hasTarget =>
      cname.isNotEmpty ||
      txt.isNotEmpty ||
      ips.isNotEmpty ||
      records.isNotEmpty;

  /// The type chips the row shows: a failure code replaces them, because no record is returned.
  List<String> get typeLabels {
    if (isRcodeFailure) return [rcode];
    final labels = <String>[];
    if (cname.isNotEmpty) labels.add('CNAME');
    if (txt.isNotEmpty) labels.add('TXT');
    if (ips.isNotEmpty) labels.add(desktopRewriteAddressChip);
    for (final record in records) {
      if (record.type.isNotEmpty && !labels.contains(record.type)) {
        labels.add(record.type);
      }
    }
    return labels;
  }

  /// Whether [query] (already lower-cased) matches any field the console searches.
  bool matches(String query) {
    if (query.isEmpty) return true;
    if (domain.toLowerCase().contains(query)) return true;
    if (cname.toLowerCase().contains(query)) return true;
    if (txt.any((item) => item.toLowerCase().contains(query))) return true;
    if (ips.any((item) => item.toLowerCase().contains(query))) return true;
    return records.any((item) => item.value.toLowerCase().contains(query));
  }

  Map<String, Object?> toJson() => {
    'domain': domain,
    if (ips.isNotEmpty) 'ips': ips,
    if (cname.isNotEmpty) 'cname': cname,
    if (txt.isNotEmpty) 'txt': txt,
    if (records.isNotEmpty)
      'records': [for (final record in records) record.toJson()],
    if (rcode.isNotEmpty) 'rcode': rcode,
    if (ttl > 0) 'ttl': ttl,
  };
}

/// `core.RewriteConfig`: the engine switch, its default lifetime and the whole rule list.
class DesktopRewriteConfig {
  const DesktopRewriteConfig({
    required this.enabled,
    required this.ttl,
    this.rules = const [],
  });

  factory DesktopRewriteConfig.fromJson(Map<String, Object?> json) =>
      DesktopRewriteConfig(
        enabled: _bool(json['enabled']),
        ttl: _int(json['ttl']),
        rules: [
          for (final item in json['rules'] as List? ?? const [])
            if (item is Map)
              DesktopRewriteRule.fromJson(item.cast<String, Object?>()),
        ],
      );

  final bool enabled;
  final int ttl;
  final List<DesktopRewriteRule> rules;

  /// The lifetime a row shows when its own rule left the field empty.
  int get effectiveTtl => ttl > 0 ? ttl : desktopRewriteDefaultTtl;

  DesktopRewriteConfig copyWith({
    bool? enabled,
    int? ttl,
    List<DesktopRewriteRule>? rules,
  }) => DesktopRewriteConfig(
    enabled: enabled ?? this.enabled,
    ttl: ttl ?? this.ttl,
    rules: rules ?? this.rules,
  );
}
