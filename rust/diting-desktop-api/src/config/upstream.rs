//! Upstream resolver, provider and bootstrap configuration.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use super::serde_util::{is_zero_f64, is_zero_i32, nullable_map, nullable_vec};

/// Upstream transport protocols, stored exactly as shared with the frontend.
pub const PROTOCOL_PLAIN: &str = "PLAIN";
/// DNS-over-HTTPS.
pub const PROTOCOL_DOH: &str = "DOH";
/// DNS-over-TLS.
pub const PROTOCOL_DOT: &str = "DOT";
/// DNS-over-QUIC.
pub const PROTOCOL_DOQ: &str = "DOQ";
/// DNS-over-HTTPS over HTTP/3.
pub const PROTOCOL_DOH3: &str = "DOH3";

/// Single-provider scheduling mode.
pub const MODE_SINGLE: &str = "single";
/// Primary/backup failover mode.
pub const MODE_PRIMARY_BACKUP: &str = "primary_backup";
/// Parallel race mode.
pub const MODE_PARALLEL_RACE: &str = "parallel_race";
/// Smart prediction mode.
pub const MODE_SMART_PREDICTION: &str = "smart_prediction";

/// One upstream provider.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ProviderConfig {
    pub id: String,
    pub protocol: String,
    pub server: String,
    pub url: String,
    #[serde(skip_serializing_if = "is_zero_i32")]
    pub weight: i32,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub pin: String,
}

/// One bootstrap DNS server.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct BootstrapServer {
    pub id: String,
    pub name: String,
    pub address: String,
    #[serde(skip_serializing_if = "is_zero_f64")]
    pub weight: f64,
}

/// Bootstrap resolver configuration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct BootstrapConfig {
    pub enabled: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub servers: Vec<BootstrapServer>,
}

impl Default for BootstrapConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            servers: default_bootstrap_servers(),
        }
    }
}

/// The default bootstrap servers (`DefaultConfig`).
pub fn default_bootstrap_servers() -> Vec<BootstrapServer> {
    vec![
        BootstrapServer {
            id: "bs-ali".to_string(),
            name: "AliDNS".to_string(),
            address: "223.5.5.5:53".to_string(),
            weight: 1.0,
        },
        BootstrapServer {
            id: "bs-dnspod".to_string(),
            name: "DNSPod".to_string(),
            address: "119.29.29.29:53".to_string(),
            weight: 1.0,
        },
    ]
}

/// The default upstream providers (`DefaultConfig`).
pub fn default_providers() -> Vec<ProviderConfig> {
    vec![
        ProviderConfig {
            id: "阿里云 (DoT)".to_string(),
            protocol: PROTOCOL_DOT.to_string(),
            server: "dns.alidns.com:853".to_string(),
            ..ProviderConfig::default()
        },
        ProviderConfig {
            id: "腾讯云 (DoT)".to_string(),
            protocol: PROTOCOL_DOT.to_string(),
            server: "dot.pub:853".to_string(),
            ..ProviderConfig::default()
        },
    ]
}

/// Whole upstream resolver configuration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ResolverConfig {
    pub mode: String,
    #[serde(deserialize_with = "nullable_vec")]
    pub providers: Vec<ProviderConfig>,
    pub bootstrap: BootstrapConfig,
    #[serde(
        skip_serializing_if = "HashMap::is_empty",
        deserialize_with = "nullable_map"
    )]
    pub conditional_routes: HashMap<String, String>,
    #[serde(skip_serializing_if = "is_zero_i32")]
    pub edns_padding: i32,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub fallback_providers: Vec<ProviderConfig>,
    #[serde(skip_serializing_if = "is_zero_i32")]
    pub fallback_timeout_ms: i32,
    /// Deliberately not skipped: `null` (use defaults) and `[]` (disable every trigger) differ.
    pub fallback_on_rcode: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fallback_on_error: Option<bool>,
}

impl Default for ResolverConfig {
    fn default() -> Self {
        Self {
            mode: MODE_PRIMARY_BACKUP.to_string(),
            providers: default_providers(),
            bootstrap: BootstrapConfig::default(),
            conditional_routes: HashMap::new(),
            edns_padding: 128,
            fallback_providers: Vec::new(),
            fallback_timeout_ms: 0,
            fallback_on_rcode: None,
            fallback_on_error: None,
        }
    }
}

impl ResolverConfig {
    /// Mirror the upstream portion of `normalizeConfig`.
    pub fn normalize(&mut self) {
        if self.mode.is_empty() {
            self.mode = MODE_PRIMARY_BACKUP.to_string();
        }
        if self.edns_padding < 0 {
            self.edns_padding = 0;
        }
        if self.bootstrap.servers.is_empty() && self.bootstrap.enabled {
            self.bootstrap.servers = default_bootstrap_servers();
        }
    }
}
