//! Server mode's upstream list: the preset rows plus the `custom_upstreams` records.
//!
//! Rows are stored with five fields (no `isCustom` — that came from the `preset_` prefix), and the
//! same filter as the tunnel catalog drops unusable rows. Validation returns a *kind*: the sentence
//! is localised by the Dart side, so nothing user-visible lives here.

use serde::Serialize;

use crate::protocol::{self, Protocol};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerUpstream {
    pub id: String,
    pub name: String,
    pub protocol: Protocol,
    /// Bare host for PLAIN / DOT, the endpoint URL for DoH.
    pub address: String,
    pub port: i32,
}

impl ServerUpstream {
    pub fn new(id: &str, name: &str, protocol: Protocol, address: &str, port: i32) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            protocol,
            address: address.to_string(),
            port,
        }
    }

    /// `host:port` for the document; DoH has no `server` field, so it is empty there.
    pub fn host_port(&self) -> String {
        protocol::server_host_port(&self.address, self.port)
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UpstreamRecord<'a> {
    id: &'a str,
    name: &'a str,
    protocol: &'a str,
    address: &'a str,
    port: i32,
}

/// Why a custom upstream was rejected; the Dart side turns this into a sentence.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UpstreamInvalid {
    NameRequired = 0,
    AddressRequired = 1,
    DohNeedsHttps = 2,
    DohInvalidUrl = 3,
    PortRange = 4,
    Ipv6Invalid = 5,
}

pub const UPSTREAM_OK: u8 = 6;

/// Reads `custom_upstreams`, dropping rows the editor could not have produced.
///
/// Note the protocol fallback: an unknown spelling becomes PLAIN here (server mode always had a
/// protocol to write), while the tunnel catalog drops the row instead.
pub fn parse_custom_upstreams(raw: Option<&str>) -> Vec<ServerUpstream> {
    let Some(raw) = raw else {
        return Vec::new();
    };
    if raw.is_empty() {
        return Vec::new();
    }
    let Ok(serde_json::Value::Array(items)) = serde_json::from_str::<serde_json::Value>(raw) else {
        return Vec::new();
    };
    let mut upstreams = Vec::with_capacity(items.len());
    for item in items {
        let serde_json::Value::Object(record) = item else {
            continue;
        };
        let text = |key: &str| record.get(key).and_then(serde_json::Value::as_str);
        let (Some(id), Some(name), Some(address)) = (text("id"), text("name"), text("address"))
        else {
            continue;
        };
        let (id, name, address) = (id.trim(), name.trim(), address.trim());
        if id.is_empty() || name.is_empty() || address.is_empty() {
            continue;
        }
        let protocol = text("protocol")
            .and_then(protocol::from_storage)
            .unwrap_or(Protocol::Plain);
        let port = match record.get("port").and_then(serde_json::Value::as_i64) {
            Some(port) => i32::try_from(port).unwrap_or(protocol::default_port(protocol)),
            None => protocol::default_port(protocol),
        };
        if protocol == Protocol::Doh {
            if !address.to_lowercase().starts_with("https://") {
                continue;
            }
        } else if !(1..=65535).contains(&port) {
            continue;
        }
        upstreams.push(ServerUpstream::new(id, name, protocol, address, port));
    }
    upstreams
}

/// The prefs document: `[{id, name, protocol, address, port}]`.
pub fn encode_custom_upstreams(upstreams: &[ServerUpstream]) -> String {
    let records: Vec<UpstreamRecord<'_>> = upstreams
        .iter()
        .map(|upstream| UpstreamRecord {
            id: &upstream.id,
            name: &upstream.name,
            protocol: protocol::storage_value(upstream.protocol),
            address: &upstream.address,
            port: upstream.port,
        })
        .collect();
    serde_json::to_string(&records).unwrap_or_else(|_| String::from("[]"))
}

/// The non-DoH address is stored bare, so a `[2001:db8::1]` paste keeps its brackets only in the UI.
pub fn normalize_address(protocol: Protocol, address: &str) -> String {
    if protocol == Protocol::Doh {
        address.trim().to_string()
    } else {
        protocol::strip_brackets(address.trim())
    }
}

/// True when the text after `https://` names a host. A bracketed address must be a real IPv6
/// literal; Dart's `Uri` parser was the original judge.
fn https_host_present(address: &str) -> bool {
    let rest = &address["https://".len()..];
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host_port = match authority.rfind('@') {
        Some(index) => &authority[index + 1..],
        None => authority,
    };
    if let Some(inner) = host_port.strip_prefix('[') {
        let Some((address, tail)) = inner.split_once(']') else {
            return false;
        };
        if !tail.is_empty() && !tail.starts_with(':') {
            return false;
        }
        return address.parse::<std::net::Ipv6Addr>().is_ok();
    }
    let host = match host_port.rfind(':') {
        Some(index) if host_port[index + 1..].chars().all(|c| c.is_ascii_digit()) => {
            &host_port[..index]
        }
        _ => host_port,
    };
    !host.is_empty() && !host.contains(char::is_whitespace)
}

/// The editor's gate: name, address, scheme, URL host, port range and a parseable IPv6 host.
pub fn validate(
    name: &str,
    protocol: Protocol,
    address: &str,
    port: i32,
) -> Result<(), UpstreamInvalid> {
    if name.trim().is_empty() {
        return Err(UpstreamInvalid::NameRequired);
    }
    let trimmed = address.trim();
    if trimmed.is_empty() {
        return Err(UpstreamInvalid::AddressRequired);
    }
    if protocol == Protocol::Doh {
        if !trimmed.to_lowercase().starts_with("https://") {
            return Err(UpstreamInvalid::DohNeedsHttps);
        }
        if !https_host_present(trimmed) {
            return Err(UpstreamInvalid::DohInvalidUrl);
        }
        return Ok(());
    }
    if !(1..=65535).contains(&port) {
        return Err(UpstreamInvalid::PortRange);
    }
    let bare = protocol::strip_brackets(trimmed);
    if bare.contains(':') && bare.parse::<std::net::Ipv6Addr>().is_err() {
        return Err(UpstreamInvalid::Ipv6Invalid);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_keeps_only_usable_rows_and_defaults_the_protocol() {
        let raw = r#"[
            {"id":"custom_doh","name":"自定义 DoH","address":"https://dns.example/dns-query","port":443,"protocol":"DOH"},
            {"id":"custom_bad","name":"坏地址","address":"http://x","port":443,"protocol":"DOH"},
            {"id":"custom_udp","name":"自定义 UDP","address":"9.9.9.9","port":5353,"protocol":"DNS"},
            {"id":"custom_unknown","name":"未知协议","address":"9.9.9.9","port":53,"protocol":"QUIC"}
        ]"#;
        let upstreams = parse_custom_upstreams(Some(raw));
        let ids: Vec<&str> = upstreams.iter().map(|item| item.id.as_str()).collect();
        assert_eq!(ids, ["custom_doh", "custom_udp", "custom_unknown"]);
        assert_eq!(upstreams[2].protocol, Protocol::Plain);
    }

    #[test]
    fn parse_is_defensive_about_shapes() {
        assert!(parse_custom_upstreams(None).is_empty());
        assert!(parse_custom_upstreams(Some("")).is_empty());
        assert!(parse_custom_upstreams(Some("[1]")).is_empty());
        assert!(parse_custom_upstreams(Some(
            r#"[{"id":"a","name":"n","address":"h","port":70000}]"#
        ))
        .is_empty());
    }

    #[test]
    fn encode_writes_five_fields_without_is_custom() {
        let text = encode_custom_upstreams(&[ServerUpstream::new(
            "custom_x",
            "X",
            Protocol::Dot,
            "dot.example",
            853,
        )]);
        assert_eq!(
            text,
            r#"[{"id":"custom_x","name":"X","protocol":"DOT","address":"dot.example","port":853}]"#
        );
    }

    #[test]
    fn validation_kinds() {
        assert_eq!(
            validate("", Protocol::Plain, "1.1.1.1", 53),
            Err(UpstreamInvalid::NameRequired)
        );
        assert_eq!(
            validate("x", Protocol::Plain, "  ", 53),
            Err(UpstreamInvalid::AddressRequired)
        );
        assert_eq!(
            validate("x", Protocol::Doh, "dns.example.com", 443),
            Err(UpstreamInvalid::DohNeedsHttps)
        );
        assert_eq!(
            validate("x", Protocol::Doh, "https://", 443),
            Err(UpstreamInvalid::DohInvalidUrl)
        );
        assert_eq!(
            validate("x", Protocol::Doh, "https://dns.example/q", 443),
            Ok(())
        );
        assert_eq!(
            validate("x", Protocol::Plain, "1.1.1.1", 0),
            Err(UpstreamInvalid::PortRange)
        );
        assert_eq!(
            validate("x", Protocol::Plain, "1.1.1.1", 70000),
            Err(UpstreamInvalid::PortRange)
        );
        assert_eq!(validate("x", Protocol::Dot, "dot.example.com", 853), Ok(()));
        assert_eq!(validate("x", Protocol::Dot, "2001:db8::1", 853), Ok(()));
        assert_eq!(
            validate("x", Protocol::Dot, "not:hextet:here", 853),
            Err(UpstreamInvalid::Ipv6Invalid)
        );
    }

    #[test]
    fn address_normalization_drops_ipv6_brackets() {
        assert_eq!(
            normalize_address(Protocol::Plain, " [2001:db8::1] "),
            "2001:db8::1"
        );
        assert_eq!(
            normalize_address(Protocol::Doh, " https://x/q "),
            "https://x/q"
        );
    }

    #[test]
    fn host_port_brackets_a_bare_ipv6_address() {
        let upstream = ServerUpstream::new("u", "U", Protocol::Dot, "dot.example", 853);
        assert_eq!(upstream.host_port(), "dot.example:853");
        let ipv6 = ServerUpstream::new("u", "U", Protocol::Plain, "2001:db8::1", 53);
        assert_eq!(ipv6.host_port(), "[2001:db8::1]:53");
    }
}
