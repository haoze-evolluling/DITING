//! The provider catalog: the preset rows, the `user_providers_json` records, and the one document
//! row both end up in.
//!
//! Parsing is the 1.4.3 filter (unknown protocol, blank id/name, a DoH row without `https://`, a
//! bad host or port are dropped) and the writer keeps the five prefs fields plus the document
//! spelling. A record that was *stored* by an older build must read back identically, which is why
//! the fields and their order are fixed here.

use serde::Serialize;

use crate::protocol::{self, Protocol};

/// One provider: a preset row, a stored custom record, or a row picked for the document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    pub id: String,
    pub name: String,
    pub protocol: Protocol,
    /// DoH endpoint; empty for PLAIN / DOT.
    pub url: String,
    /// PLAIN / DOT host; empty for DoH.
    pub host: String,
    pub port: i32,
}

impl Provider {
    pub fn new(id: &str, name: &str, protocol: Protocol, url: &str, host: &str, port: i32) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            protocol,
            url: url.to_string(),
            host: host.to_string(),
            port,
        }
    }

    /// `host:port`, bracketed when the host is a bare IPv6 literal.
    pub fn host_port(&self) -> String {
        protocol::join_host_port(&self.host, self.port)
    }

    /// What the management UI edits: the DoH URL, or `host:port`.
    pub fn address(&self) -> String {
        if self.protocol == Protocol::Doh {
            self.url.clone()
        } else {
            self.host_port()
        }
    }
}

/// `user_providers_json` row, exactly as 1.4.3 wrote it.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProviderRecord<'a> {
    id: &'a str,
    name: &'a str,
    protocol: &'a str,
    url: &'a str,
    host: &'a str,
    port: i32,
}

/// `_splitAddress`: DoH keeps the whole text as its URL, everything else becomes host + port.
///
/// A missing colon means "host only, default port"; a non-numeric port also falls back to the
/// protocol default, which is what let 1.4.3 store `dot.example:abc` as DoT/853.
pub fn split_address(protocol: Protocol, address: &str) -> (String, String, i32) {
    let trimmed = address.trim();
    if protocol == Protocol::Doh {
        return (trimmed.to_string(), String::new(), 853);
    }
    let Some(separator) = trimmed.rfind(':') else {
        return (
            String::new(),
            trimmed.to_string(),
            protocol::default_port(protocol),
        );
    };
    if separator == 0 {
        return (
            String::new(),
            trimmed.to_string(),
            protocol::default_port(protocol),
        );
    }
    let host = &trimmed[..separator];
    let port = trimmed[separator + 1..]
        .parse::<i32>()
        .unwrap_or_else(|_| protocol::default_port(protocol));
    (String::new(), host.to_string(), port)
}

/// Reads `user_providers_json`, dropping the rows 1.4.3 drops.
///
/// A field of the wrong JSON type makes the row unusable; the Dart original threw on those, which
/// would have aborted the whole config build, so a corrupt file now simply loses that row.
pub fn parse_user_providers(raw: Option<&str>) -> Vec<Provider> {
    let Some(raw) = raw else {
        return Vec::new();
    };
    if raw.is_empty() {
        return Vec::new();
    }
    let Ok(serde_json::Value::Array(items)) = serde_json::from_str::<serde_json::Value>(raw) else {
        return Vec::new();
    };
    let mut providers = Vec::with_capacity(items.len());
    for item in items {
        let serde_json::Value::Object(record) = item else {
            continue;
        };
        let text = |key: &str| record.get(key).and_then(serde_json::Value::as_str);
        let Some(protocol) = text("protocol").and_then(protocol::from_storage) else {
            continue;
        };
        let (Some(id), Some(name)) = (text("id"), text("name")) else {
            continue;
        };
        if id.is_empty() || name.is_empty() {
            continue;
        }
        let url = text("url").unwrap_or("").trim().to_string();
        let host = text("host").unwrap_or("").trim().to_string();
        let port = match record.get("port").and_then(serde_json::Value::as_i64) {
            Some(port) => port as i32,
            None => protocol::default_port(protocol),
        };
        if protocol == Protocol::Doh {
            if !url.to_lowercase().starts_with("https://") {
                continue;
            }
            providers.push(Provider::new(id, name, protocol, &url, "", port));
        } else {
            if host.is_empty() || !(1..=65535).contains(&port) {
                continue;
            }
            providers.push(Provider::new(id, name, protocol, "", &host, port));
        }
    }
    providers
}

/// The prefs document: `[{id, name, protocol, url, host, port}]`.
pub fn encode_user_providers(providers: &[Provider]) -> String {
    let records: Vec<ProviderRecord<'_>> = providers
        .iter()
        .map(|provider| ProviderRecord {
            id: &provider.id,
            name: &provider.name,
            protocol: protocol::storage_value(provider.protocol),
            url: &provider.url,
            host: &provider.host,
            port: provider.port,
        })
        .collect();
    serde_json::to_string(&records).unwrap_or_else(|_| String::from("[]"))
}

/// Add-or-replace by id: the list order survives an edit, and a new id appends.
pub fn upsert_user_provider(
    providers: &[Provider],
    id: &str,
    name: &str,
    protocol: Protocol,
    address: &str,
) -> Vec<Provider> {
    let (url, host, port) = split_address(protocol, address);
    let record = Provider::new(id, name.trim(), protocol, &url, &host, port);
    let mut output: Vec<Provider> = Vec::with_capacity(providers.len() + 1);
    let mut replaced = false;
    for provider in providers {
        if provider.id == id {
            output.push(record.clone());
            replaced = true;
        } else {
            output.push(provider.clone());
        }
    }
    if !replaced {
        output.push(record);
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(id: &str, name: &str, protocol: &str, url: &str, host: &str, port: i32) -> String {
        format!(
            r#"{{"id":"{id}","name":"{name}","protocol":"{protocol}","url":"{url}","host":"{host}","port":{port}}}"#
        )
    }

    #[test]
    fn split_address_matches_the_editor() {
        assert_eq!(
            split_address(Protocol::Doh, " https://dns.example/query "),
            ("https://dns.example/query".to_string(), String::new(), 853)
        );
        assert_eq!(
            split_address(Protocol::Dot, "dot.example.com:8853"),
            (String::new(), "dot.example.com".to_string(), 8853)
        );
        assert_eq!(
            split_address(Protocol::Plain, "dns.example.com"),
            (String::new(), "dns.example.com".to_string(), 53)
        );
        assert_eq!(
            split_address(Protocol::Dot, "dot.example.com:abc"),
            (String::new(), "dot.example.com".to_string(), 853)
        );
        // A colon at the very start is not a separator: the whole text stays the host.
        assert_eq!(
            split_address(Protocol::Plain, ":53"),
            (String::new(), ":53".to_string(), 53)
        );
    }

    #[test]
    fn parse_drops_the_rows_143_drops() {
        let raw = format!(
            "[{},{},{},{}]",
            record("a", "无 https", "DOH", "http://x", "", 0),
            record("b", "端口越界", "DOT", "", "x", 70000),
            record("c", "未知协议", "QUIC", "", "x", 0),
            record("d", "可用", "DOT", "", "d.example", 853),
        );
        let providers = parse_user_providers(Some(&raw));
        assert_eq!(providers.len(), 1);
        assert_eq!(providers[0].id, "d");
        assert_eq!(providers[0].host_port(), "d.example:853");
    }

    #[test]
    fn parse_is_defensive_about_shapes() {
        assert!(parse_user_providers(None).is_empty());
        assert!(parse_user_providers(Some("")).is_empty());
        assert!(parse_user_providers(Some("not json")).is_empty());
        assert!(parse_user_providers(Some("{}")).is_empty());
        assert!(parse_user_providers(Some("[1,2]")).is_empty());
        // Wrongly typed fields lose the row instead of aborting the build.
        assert!(parse_user_providers(Some(r#"[{"id":1,"name":"x","protocol":"DOT"}]"#)).is_empty());
        assert!(parse_user_providers(Some(
            r#"[{"id":"a","name":"","protocol":"DOT","host":"h","port":853}]"#
        ))
        .is_empty());
    }

    #[test]
    fn parse_keeps_a_doh_row_with_uppercase_https() {
        let raw = format!("[{}]", record("a", "DoH", "DOH", "HTTPS://x.test/q", "", 0));
        let providers = parse_user_providers(Some(&raw));
        assert_eq!(providers.len(), 1);
        assert_eq!(providers[0].address(), "HTTPS://x.test/q");
    }

    #[test]
    fn encode_keeps_the_prefs_field_order_and_spelling() {
        let providers = vec![Provider::new(
            "user_1",
            "自建 DoH",
            Protocol::Doh,
            "https://dns.example/query",
            "",
            853,
        )];
        assert_eq!(
            encode_user_providers(&providers),
            r#"[{"id":"user_1","name":"自建 DoH","protocol":"DOH","url":"https://dns.example/query","host":"","port":853}]"#
        );
    }

    #[test]
    fn upsert_appends_and_replaces_in_place() {
        let existing = vec![
            Provider::new("user_1", "旧名", Protocol::Dot, "", "old", 853),
            Provider::new("user_2", "保留", Protocol::Plain, "", "1.1.1.1", 53),
        ];
        let updated = upsert_user_provider(&existing, "user_1", " 新名 ", Protocol::Dot, "new:853");
        assert_eq!(updated.len(), 2);
        assert_eq!(updated[0].name, "新名");
        assert_eq!(updated[0].host, "new");
        assert_eq!(updated[1].id, "user_2");

        let added = upsert_user_provider(&existing, "user_3", "新增", Protocol::Doh, "https://x/q");
        assert_eq!(added.len(), 3);
        assert_eq!(added[2].id, "user_3");
        assert_eq!(added[2].url, "https://x/q");
    }
}
