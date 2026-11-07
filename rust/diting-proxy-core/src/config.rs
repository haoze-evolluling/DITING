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

    let protocol = go_lower(go_trim_space(&config.protocol)).into_owned();
    if protocol != "socks5" && protocol != "http" {
        return Err(format!("unsupported outbound proxy protocol {protocol:?}"));
    }

    let Some(address) = parse_ip(go_trim_space(&config.host)) else {
        return Err("outbound proxy host must be 127.0.0.1 or ::1".to_string());
    };
    if !is_loopback(&address) {
        return Err("outbound proxy host must be 127.0.0.1 or ::1".to_string());
    }

    if config.port < 1 || config.port > 65535 {
        return Err("outbound proxy port must be between 1 and 65535".to_string());
    }
    if config.username.len() > 255 || config.password.len() > 255 {
        return Err("SOCKS5 credentials must not exceed 255 bytes".to_string());
    }

    let scope = go_lower(go_trim_space(&config.scope)).into_owned();
    let scope = if scope == SCOPE_APPS {
        scope
    } else {
        SCOPE_ALL.to_string()
    };

    let mut uids: Vec<i64> = Vec::new();
    for uid in config.uids {
        if uid > 0 && !uids.contains(&uid) {
            uids.push(uid);
        }
    }

    Ok(NormalizedConfig {
        enabled: true,
        protocol,
        host: ip_text(&address),
        port: config.port,
        scope,
        uids,
    })
}

#[cfg(test)]
mod tests;
