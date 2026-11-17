//! The desktop upstream settings the resolver wrapper consumes.
//!
//! These mirror `core.ResolverConfig`, but without the JSON tags: `diting-desktop-api` owns the
//! wire shape, and the service converts it here so the resolver crate stays independent of the
//! config file.

use std::collections::BTreeMap;

#[derive(Debug, Clone, Default)]
pub struct ProviderSettings {
    pub id: String,
    pub protocol: String,
    pub server: String,
    pub url: String,
    pub weight: i64,
    pub pin: String,
}

impl ProviderSettings {
    pub fn plain(server: impl Into<String>) -> Self {
        Self {
            protocol: "PLAIN".to_string(),
            server: server.into(),
            ..Self::default()
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct BootstrapServerSettings {
    pub id: String,
    pub name: String,
    pub address: String,
    pub weight: f64,
}

#[derive(Debug, Clone, Default)]
pub struct BootstrapSettings {
    pub enabled: bool,
    pub servers: Vec<BootstrapServerSettings>,
}

#[derive(Debug, Clone, Default)]
pub struct ResolverSettings {
    pub mode: String,
    pub providers: Vec<ProviderSettings>,
    pub bootstrap: BootstrapSettings,
    pub conditional_routes: BTreeMap<String, String>,
    pub edns_padding: i64,
    pub fallback_providers: Vec<ProviderSettings>,
    pub fallback_timeout_ms: i64,
    /// `None` means "not expressed" and selects the default FAIL/REFUSED set; `Some([])` means the
    /// user explicitly removed every response code trigger.
    pub fallback_on_rcode: Option<Vec<i32>>,
    pub fallback_on_error: Option<bool>,
    pub race_max_parallel: i64,
}

/// `DefaultFallbackTimeoutMs`.
pub const DEFAULT_FALLBACK_TIMEOUT_MS: i64 = 2000;

/// `DefaultFallbackRcodes`: SERVFAIL and REFUSED, deliberately not NXDOMAIN.
pub const DEFAULT_FALLBACK_RCODES: [i32; 2] = [2, 5];

impl ResolverSettings {
    pub fn effective_timeout(&self) -> Option<std::time::Duration> {
        if self.fallback_providers.is_empty() {
            return None;
        }
        let millis = if self.fallback_timeout_ms > 0 {
            self.fallback_timeout_ms
        } else {
            DEFAULT_FALLBACK_TIMEOUT_MS
        };
        Some(std::time::Duration::from_millis(millis as u64))
    }

    pub fn effective_rcodes(&self) -> Vec<i32> {
        self.fallback_on_rcode
            .clone()
            .unwrap_or_else(|| DEFAULT_FALLBACK_RCODES.to_vec())
    }

    pub fn fallback_on_error(&self) -> bool {
        self.fallback_on_error.unwrap_or(true)
    }
}
