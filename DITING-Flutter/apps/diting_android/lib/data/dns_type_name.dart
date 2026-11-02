/// DNS record type number to display name, with a `TYPE$n` fallback. Lives in `data/` because the
/// dashboard aggregation needs it too.
library;

String dnsTypeName(int type) => switch (type) {
  1 => 'A',
  28 => 'AAAA',
  5 => 'CNAME',
  15 => 'MX',
  16 => 'TXT',
  2 => 'NS',
  12 => 'PTR',
  255 => 'ANY',
  _ => 'TYPE$type',
};
