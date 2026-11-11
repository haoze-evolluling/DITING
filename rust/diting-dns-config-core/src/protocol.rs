//! The upstream protocol as the app stores it, and the two spellings the engine reads.
//!
//! 1.4.3 stored `DNS` / `DOH` / `DOT` in the prefs, while `ApplyDNSConfig` reads `PLAIN` / `DOH` /
//! `DOT`. The go-side table already lives in `diting-config-core` (the engine validates pushed
//! configs against it), so this module only adds the storage spelling on top instead of a second
//! copy of the engine's names.

pub use diting_config_core::protocol::Protocol;

pub const STORAGE_DNS: &str = "DNS";
pub const STORAGE_DOH: &str = "DOH";
pub const STORAGE_DOT: &str = "DOT";

/// `DnsProtocol.fromStorage`: case-insensitive, anything else is not a protocol at all.
pub fn from_storage(value: &str) -> Option<Protocol> {
    match value.to_uppercase().as_str() {
        STORAGE_DNS => Some(Protocol::Plain),
        STORAGE_DOH => Some(Protocol::Doh),
        STORAGE_DOT => Some(Protocol::Dot),
        _ => None,
    }
}

/// The prefs spelling, for `user_providers_json` and `custom_upstreams`.
pub fn storage_value(protocol: Protocol) -> &'static str {
    match protocol {
        Protocol::Doh => STORAGE_DOH,
        Protocol::Dot => STORAGE_DOT,
        // `Plain` is `DNS` in the prefs and `PLAIN` in the document; `Doq` never reaches the app.
        _ => STORAGE_DNS,
    }
}

/// The document spelling (`PLAIN` / `DOH` / `DOT`).
pub fn go_value(protocol: Protocol) -> &'static str {
    protocol.name()
}

/// Plain DNS falls back to 53, DoT to 853.
pub fn default_port(protocol: Protocol) -> i32 {
    if protocol == Protocol::Dot {
        853
    } else {
        53
    }
}

/// `block_response_mode` (`nxdomain` / `nodata` / `refused` / `zero_address`) to the document's
/// `blockResponse`. An unknown value is the 1.4.3 default, `NXDOMAIN` — note this is *not* the
/// engine's own table, where unknown means `CUSTOM_IP`.
pub fn block_response(storage: &str) -> &'static str {
    match storage {
        "nodata" => "NODATA",
        "refused" => "REFUSED",
        "zero_address" => "CUSTOM_IP",
        _ => "NXDOMAIN",
    }
}

/// `joinHostPort`: bracketing a bare IPv6 host so the engine can parse the result.
pub fn join_host_port(host: &str, port: i32) -> String {
    if host.contains(':') && !host.starts_with('[') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

/// `ServerUpstream.hostPort`: the server-mode address is a bare host, so an address that already
/// carries a colon is bracketed — including the odd `host:port` input this inherits from 1.4.3.
pub fn server_host_port(address: &str, port: i32) -> String {
    if address.contains(':') {
        let bare = strip_brackets(address);
        format!("[{bare}]:{port}")
    } else {
        format!("{address}:{port}")
    }
}

/// Drops one leading `[` and one trailing `]`.
pub fn strip_brackets(value: &str) -> String {
    let mut result = value;
    if let Some(rest) = result.strip_prefix('[') {
        result = rest;
    }
    if let Some(rest) = result.strip_suffix(']') {
        result = rest;
    }
    result.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn storage_round_trip_and_rejects_unknown() {
        assert_eq!(from_storage("dns"), Some(Protocol::Plain));
        assert_eq!(from_storage("DOH"), Some(Protocol::Doh));
        assert_eq!(from_storage("Dot"), Some(Protocol::Dot));
        assert_eq!(from_storage("QUIC"), None);
        assert_eq!(storage_value(Protocol::Plain), "DNS");
        assert_eq!(storage_value(Protocol::Doh), "DOH");
        assert_eq!(storage_value(Protocol::Dot), "DOT");
        assert_eq!(go_value(Protocol::Plain), "PLAIN");
        assert_eq!(go_value(Protocol::Doh), "DOH");
        assert_eq!(go_value(Protocol::Dot), "DOT");
    }

    #[test]
    fn default_ports_are_53_and_853() {
        assert_eq!(default_port(Protocol::Plain), 53);
        assert_eq!(default_port(Protocol::Doh), 53);
        assert_eq!(default_port(Protocol::Dot), 853);
    }

    #[test]
    fn block_response_falls_back_to_nxdomain() {
        assert_eq!(block_response("nodata"), "NODATA");
        assert_eq!(block_response("refused"), "REFUSED");
        assert_eq!(block_response("zero_address"), "CUSTOM_IP");
        assert_eq!(block_response("nxdomain"), "NXDOMAIN");
        assert_eq!(block_response(""), "NXDOMAIN");
    }

    #[test]
    fn host_port_bracketing() {
        assert_eq!(join_host_port("1.1.1.1", 53), "1.1.1.1:53");
        assert_eq!(join_host_port("::1", 853), "[::1]:853");
        assert_eq!(join_host_port("[::1]", 853), "[::1]:853");
        assert_eq!(server_host_port("1.1.1.1", 53), "1.1.1.1:53");
        assert_eq!(server_host_port("2001:db8::1", 53), "[2001:db8::1]:53");
        assert_eq!(server_host_port("[2001:db8::1]", 53), "[2001:db8::1]:53");
    }

    #[test]
    fn brackets_are_stripped_once_from_each_side() {
        assert_eq!(strip_brackets("[::1]"), "::1");
        assert_eq!(strip_brackets("::1"), "::1");
        assert_eq!(strip_brackets("[::1"), "::1");
    }
}
