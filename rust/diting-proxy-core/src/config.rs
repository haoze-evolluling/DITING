//! The normalized outbound proxy settings.
//!
//! Go still decodes the JSON (`encoding/json` is the config format, and its error text is what the
//! UI shows for a malformed document); everything after the decode happens here so there is one
//! copy of the rules:
//!
//! * protocol is trimmed, lowercased and must be `socks5` or `http`;
//! * the host is trimmed, must parse as an IP literal (`net.ParseIP`) and must be loopback, then it
//!   is stored in `net.IP.String` form (`::ffff:127.0.0.1` becomes `127.0.0.1`);
//! * the port must be 1..=65535;
//! * neither credential may exceed 255 bytes (the SOCKS5 length prefix is one byte);
//! * the scope is trimmed, lowercased, and anything but `apps` becomes `all`;
//! * only positive UIDs are kept, deduplicated.
//!
//! A disabled config is returned untouched: the old code returned the decoded struct before any
//! validation, so an invalid protocol behind `"enabled": false` never failed a config push.

use diting_go_compat::text::{go_lower, go_trim_space};

use crate::addr::{ip_text, is_loopback, parse_ip};

/// Scope value that puts only the selected UIDs behind the proxy.
pub const SCOPE_APPS: &str = "apps";
/// Scope value that proxies every flow.
pub const SCOPE_ALL: &str = "all";

/// The decoded config, one-to-one with the Go struct's JSON fields.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ProxyConfig {
    pub enabled: bool,
    pub protocol: String,
    pub host: String,
    pub port: i64,
    pub username: String,
    pub password: String,
    pub scope: String,
    pub uids: Vec<i64>,
}

/// The config after validation: `host` is `net.IP.String` form and `uids` only holds the positive,
/// deduplicated IDs.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NormalizedConfig {
    pub enabled: bool,
    pub protocol: String,
    pub host: String,
    pub port: i64,
    pub scope: String,
    pub uids: Vec<i64>,
}

impl NormalizedConfig {
    /// `outboundProxyConfig.perApp`: only the selected UIDs are proxied.
    pub fn per_app(&self) -> bool {
        self.enabled && self.scope == SCOPE_APPS
    }
}

/// The protocol after the engine's trim/lowercase rule; `None` means it is not `socks5` or `http`.
pub fn normalize_protocol(value: &str) -> Option<&'static str> {
    match go_lower(go_trim_space(value)).as_ref() {
        "socks5" => Some("socks5"),
        "http" => Some("http"),
        _ => None,
    }
}

/// The canonical `net.IP.String` form of a loopback host, or `None` when it is not one.
pub fn normalize_host(value: &str) -> Option<String> {
    let address = parse_ip(go_trim_space(value))?;
    is_loopback(&address).then(|| ip_text(&address))
}

/// The SOCKS5 / HTTP CONNECT port range.
pub fn valid_port(port: i64) -> bool {
    (1..=65535).contains(&port)
}

/// The one-byte SOCKS5 length prefixes cap both credentials at 255 UTF-8 bytes.
pub fn valid_credentials(username: &str, password: &str) -> bool {
    username.len() <= 255 && password.len() <= 255
}

/// The scope after the engine's trim/lowercase rule; anything but `apps` becomes `all`.
pub fn normalize_scope(value: &str) -> &'static str {
    if go_lower(go_trim_space(value)).as_ref() == SCOPE_APPS {
        SCOPE_APPS
    } else {
        SCOPE_ALL
    }
}

/// Validates and normalizes one decoded config.
pub fn normalize(config: ProxyConfig) -> Result<NormalizedConfig, String> {
    if !config.enabled {
        return Ok(NormalizedConfig {
            enabled: false,
            protocol: config.protocol,
            host: config.host,
            port: config.port,
            scope: config.scope,
            uids: Vec::new(),
        });
    }

    let Some(protocol) = normalize_protocol(&config.protocol) else {
        let protocol = go_lower(go_trim_space(&config.protocol)).into_owned();
        return Err(format!("unsupported outbound proxy protocol {protocol:?}"));
    };

    let Some(host) = normalize_host(&config.host) else {
        return Err("outbound proxy host must be 127.0.0.1 or ::1".to_string());
    };

    if !valid_port(config.port) {
        return Err("outbound proxy port must be between 1 and 65535".to_string());
    }
    if !valid_credentials(&config.username, &config.password) {
        return Err("SOCKS5 credentials must not exceed 255 bytes".to_string());
    }

    let scope = normalize_scope(&config.scope).to_string();

    let mut uids: Vec<i64> = Vec::new();
    for uid in config.uids {
        if uid > 0 && !uids.contains(&uid) {
            uids.push(uid);
        }
    }

    Ok(NormalizedConfig {
        enabled: true,
        protocol: protocol.to_string(),
        host,
        port: config.port,
        scope,
        uids,
    })
}

#[cfg(test)]
mod tests;
