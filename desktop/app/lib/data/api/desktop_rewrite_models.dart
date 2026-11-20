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

const List<String> desktopRewriteRcodes = [
  'NOERROR',
  'FORMERR',
  'SERVFAIL',
  'NXDOMAIN',
  'NOTIMP',
  'REFUSED',
];

const int desktopRewriteDefaultTtl = 60;

const String desktopRewriteAddressChip = 'A / AAAA';

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

  final String domain;
  final List<String> ips;
  final String cname;
  final List<String> txt;
  final List<DesktopRewriteRecord> records;

  final String rcode;

  final int ttl;

  bool get isRcodeFailure => rcode.isNotEmpty && rcode != 'NOERROR';

  bool get hasTarget =>
      cname.isNotEmpty ||
      txt.isNotEmpty ||
      ips.isNotEmpty ||
      records.isNotEmpty;

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
