pub use diting_config_core::protocol::Protocol;

pub const STORAGE_DNS: &str = "DNS";
pub const STORAGE_DOH: &str = "DOH";
pub const STORAGE_DOT: &str = "DOT";

pub fn from_storage(value: &str) -> Option<Protocol> {
    match value.to_uppercase().as_str() {
        STORAGE_DNS => Some(Protocol::Plain),
        STORAGE_DOH => Some(Protocol::Doh),
        STORAGE_DOT => Some(Protocol::Dot),
        _ => None,
    }
}

pub fn storage_value(protocol: Protocol) -> &'static str {
    match protocol {
        Protocol::Doh => STORAGE_DOH,
        Protocol::Dot => STORAGE_DOT,
        _ => STORAGE_DNS,
    }
}

pub fn go_value(protocol: Protocol) -> &'static str {
    protocol.name()
}

pub fn default_port(protocol: Protocol) -> i32 {
    if protocol == Protocol::Dot {
        853
    } else {
        53
    }
}

pub fn block_response(storage: &str) -> &'static str {
    match storage {
        "nodata" => "NODATA",
        "refused" => "REFUSED",
        "zero_address" => "CUSTOM_IP",
        _ => "NXDOMAIN",
    }
}

pub fn join_host_port(host: &str, port: i32) -> String {
    if host.contains(':') && !host.starts_with('[') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

pub fn server_host_port(address: &str, port: i32) -> String {
    if address.contains(':') {
        let bare = strip_brackets(address);
        format!("[{bare}]:{port}")
    } else {
        format!("{address}:{port}")
    }
}

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
