library;

Map<String, Object?> rewritePayload({
  bool enabled = true,
  int ttl = 60,
  List<Map<String, Object?>>? rules,
}) => {
  'enabled': enabled,
  'ttl': ttl,
  'rules':
      rules ??
      const [
        {
          'domain': 'host.lan',
          'ips': ['192.168.1.100', 'fd00::100'],
          'ttl': 120,
        },
        {'domain': 'alias.lan', 'cname': 'target.lan'},
        {
          'domain': 'text.lan',
          'txt': ['v=spf1 ~all'],
        },
        {
          'domain': 'mail.lan',
          'records': [
            {'type': 'MX', 'value': '32 mail.lan'},
            {'type': 'A', 'value': '10.0.0.5'},
          ],
        },
        {'domain': 'gone.lan', 'rcode': 'NXDOMAIN'},
      ],
};
