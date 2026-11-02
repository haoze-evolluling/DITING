/// Fixtures for the desktop rewrite page: the engine config plus the rule list the service stores
/// with it, so the fake answers `/status` and `/dns/rewrite/rules` from one source.
library;

/// A `GET /api/v1/status` payload's `rewrite` field and the answer of `/dns/rewrite/rules`. The
/// service stores both in one config, so the fake does too.
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
