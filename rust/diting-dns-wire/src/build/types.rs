//! Record type, class and EDNS option codes used by the builder.
//!
//! These are the numeric values an encoder writes into the wire; they are re-exported from the
//! crate root so callers do not have to spell magic numbers.

/// `A` record (RFC 1035).
pub const TYPE_A: u16 = 1;
/// `NS` record (RFC 1035).
pub const TYPE_NS: u16 = 2;
/// `CNAME` record (RFC 1035).
pub const TYPE_CNAME: u16 = 5;
/// `SOA` record (RFC 1035).
pub const TYPE_SOA: u16 = 6;
/// `PTR` record (RFC 1035).
pub const TYPE_PTR: u16 = 12;
/// `HINFO` record (RFC 1035).
pub const TYPE_HINFO: u16 = 13;
/// `MX` record (RFC 1035).
pub const TYPE_MX: u16 = 15;
/// `TXT` record (RFC 1035).
pub const TYPE_TXT: u16 = 16;
/// `AAAA` record (RFC 3596).
pub const TYPE_AAAA: u16 = 28;
/// `SRV` record (RFC 2782).
pub const TYPE_SRV: u16 = 33;
/// `NAPTR` record (RFC 3403).
pub const TYPE_NAPTR: u16 = 35;
/// `OPT` pseudo-record (RFC 6891).
pub const TYPE_OPT: u16 = 41;
/// `SVCB` record (RFC 9460).
pub const TYPE_SVCB: u16 = 64;
/// `HTTPS` record (RFC 9460).
pub const TYPE_HTTPS: u16 = 65;
/// `ANY` query type (RFC 1035), used when synthesizing an all-records answer.
pub const TYPE_ANY: u16 = 255;
/// `CAA` record (RFC 8659).
pub const TYPE_CAA: u16 = 257;

/// Internet class.
pub const CLASS_IN: u16 = 1;
/// Chaos class.
pub const CLASS_CH: u16 = 3;
/// `ANY` class.
pub const CLASS_ANY: u16 = 255;
/// `NONE` class (used by dynamic update, RFC 2136).
pub const CLASS_NONE: u16 = 254;

/// EDNS NSID option (RFC 5001).
pub const OPTION_NSID: u16 = 3;
/// EDNS Client Subnet option (RFC 7871).
pub const OPTION_ECS: u16 = 8;
/// EDNS Cookie option (RFC 7873).
pub const OPTION_COOKIE: u16 = 10;
/// EDNS Padding option (RFC 7830).
pub const OPTION_PADDING: u16 = 12;
/// EDNS Extended DNS Error option (RFC 8914).
pub const OPTION_EDE: u16 = 15;

/// SVCB `alpn` parameter key (RFC 9460).
pub const SVCB_KEY_ALPN: u16 = 1;
/// SVCB `no-default-alpn` parameter key (RFC 9460).
pub const SVCB_KEY_NO_DEFAULT_ALPN: u16 = 2;
/// SVCB `port` parameter key (RFC 9460).
pub const SVCB_KEY_PORT: u16 = 3;
/// SVCB `ipv4hint` parameter key (RFC 9460).
pub const SVCB_KEY_IPV4HINT: u16 = 4;
/// SVCB `ech` parameter key (RFC 9460).
pub const SVCB_KEY_ECH: u16 = 5;
/// SVCB `ipv6hint` parameter key (RFC 9460).
pub const SVCB_KEY_IPV6HINT: u16 = 6;
/// SVCB `dohpath` parameter key (RFC 9461).
pub const SVCB_KEY_DOHPATH: u16 = 7;
