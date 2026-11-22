pub const TYPE_A: u16 = 1;
pub const TYPE_NS: u16 = 2;
pub const TYPE_CNAME: u16 = 5;
pub const TYPE_SOA: u16 = 6;
pub const TYPE_PTR: u16 = 12;
pub const TYPE_HINFO: u16 = 13;
pub const TYPE_MX: u16 = 15;
pub const TYPE_TXT: u16 = 16;
pub const TYPE_AAAA: u16 = 28;
pub const TYPE_SRV: u16 = 33;
pub const TYPE_NAPTR: u16 = 35;
pub const TYPE_OPT: u16 = 41;
pub const TYPE_SVCB: u16 = 64;
pub const TYPE_HTTPS: u16 = 65;
pub const TYPE_ANY: u16 = 255;
pub const TYPE_CAA: u16 = 257;

pub const CLASS_IN: u16 = 1;
pub const CLASS_CH: u16 = 3;
pub const CLASS_ANY: u16 = 255;
pub const CLASS_NONE: u16 = 254;

pub const OPTION_NSID: u16 = 3;
pub const OPTION_ECS: u16 = 8;
pub const OPTION_COOKIE: u16 = 10;
pub const OPTION_PADDING: u16 = 12;
pub const OPTION_EDE: u16 = 15;

pub const SVCB_KEY_ALPN: u16 = 1;
pub const SVCB_KEY_NO_DEFAULT_ALPN: u16 = 2;
pub const SVCB_KEY_PORT: u16 = 3;
pub const SVCB_KEY_IPV4HINT: u16 = 4;
pub const SVCB_KEY_ECH: u16 = 5;
pub const SVCB_KEY_IPV6HINT: u16 = 6;
pub const SVCB_KEY_DOHPATH: u16 = 7;
