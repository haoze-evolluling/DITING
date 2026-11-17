//! Hosts, rebinding, access control, rate limiting, DNS64 and ECS configuration.

use serde::{Deserialize, Serialize};

use super::serde_util::nullable_vec;

/// Default TTL for hosts entries.
pub const DEFAULT_HOSTS_TTL: u32 = 60;
/// RFC 6052 well-known DNS64 prefix.
pub const WELL_KNOWN_DNS64_PREFIX: &str = "64:ff9b::/96";

/// Hosts-file resolver configuration.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct HostsConfig {
    pub enabled: bool,
    pub use_system_host: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub custom_files: Vec<String>,
    pub ttl: u32,
}

impl Default for HostsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            use_system_host: true,
            custom_files: Vec::new(),
            ttl: DEFAULT_HOSTS_TTL,
        }
    }
}

/// DNS rebinding protection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct RebindConfig {
    pub enabled: bool,
    pub allowed_domains: Vec<String>,
}

impl Default for RebindConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            allowed_domains: vec![
                "localhost".to_string(),
                ".local".to_string(),
                ".lan".to_string(),
                ".home.arpa".to_string(),
                "in-addr.arpa".to_string(),
                "ip6.arpa".to_string(),
            ],
        }
    }
}

/// Client access-control configuration. Empty lists allow everyone.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct AccessControlConfig {
    #[serde(deserialize_with = "nullable_vec")]
    pub allowed_clients: Vec<String>,
    #[serde(deserialize_with = "nullable_vec")]
    pub blocked_clients: Vec<String>,
}

/// Client request rate-limiting configuration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct RateLimitConfig {
    pub enabled: bool,
    pub rate: f64,
    pub burst: i32,
    pub ipv4_prefix: i32,
    pub ipv6_prefix: i32,
    #[serde(rename = "exemptIPs", deserialize_with = "nullable_vec")]
    pub exempt_ips: Vec<String>,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            rate: 50.0,
            burst: 100,
            ipv4_prefix: 32,
            ipv6_prefix: 128,
            exempt_ips: vec!["127.0.0.1".to_string(), "::1".to_string()],
        }
    }
}

/// DNS64 / NAT64 synthesis configuration.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DNS64Config {
    pub enabled: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub prefixes: Vec<String>,
}

impl Default for DNS64Config {
    fn default() -> Self {
        Self {
            enabled: false,
            prefixes: vec![WELL_KNOWN_DNS64_PREFIX.to_string()],
        }
    }
}

/// EDNS Client Subnet privacy and forwarding policy.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ECSConfig {
    pub enabled: bool,
    #[serde(rename = "stripECS")]
    pub strip_ecs: bool,
    pub custom_subnet: String,
}

impl Default for ECSConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            strip_ecs: true,
            custom_subnet: String::new(),
        }
    }
}
