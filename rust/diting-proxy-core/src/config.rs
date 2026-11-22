use diting_go_compat::text::{go_lower, go_trim_space};

use crate::addr::{ip_text, is_loopback, parse_ip};

pub const SCOPE_APPS: &str = "apps";
pub const SCOPE_ALL: &str = "all";

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
    pub fn per_app(&self) -> bool {
        self.enabled && self.scope == SCOPE_APPS
    }
}

pub fn normalize_protocol(value: &str) -> Option<&'static str> {
    match go_lower(go_trim_space(value)).as_ref() {
        "socks5" => Some("socks5"),
        "http" => Some("http"),
        _ => None,
    }
}

pub fn normalize_host(value: &str) -> Option<String> {
    let address = parse_ip(go_trim_space(value))?;
    is_loopback(&address).then(|| ip_text(&address))
}

pub fn valid_port(port: i64) -> bool {
    (1..=65535).contains(&port)
}

pub fn valid_credentials(username: &str, password: &str) -> bool {
    username.len() <= 255 && password.len() <= 255
}

pub fn normalize_scope(value: &str) -> &'static str {
    if go_lower(go_trim_space(value)).as_ref() == SCOPE_APPS {
        SCOPE_APPS
    } else {
        SCOPE_ALL
    }
}

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
