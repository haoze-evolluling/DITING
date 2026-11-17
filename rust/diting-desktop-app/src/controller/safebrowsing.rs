//! Reputation lookup and parental control (`/api/v1/filter/safebrowsing`).
//!
//! The verdict runs inside the DNS stage; this module only exposes the configuration and the
//! cumulative counters, plus the block-answer policy the stage will apply, so the UI can explain
//! what a hit actually returns.

use serde::{Deserialize, Serialize};

use diting_desktop_api::config::security::SafeBrowsingConfig;
use diting_desktop_core::safebrowsing::SafeBrowsingStats;

use crate::controller::ControllerError;
use crate::AppRuntime;

/// `ipc.ConfigureSafeBrowsingRequest`; every field is optional so "off" and "unchanged" differ.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureSafeBrowsingRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub parental_enabled: Option<bool>,
    #[serde(default)]
    pub timeout_ms: Option<i32>,
    #[serde(default)]
    pub cache_size: Option<i32>,
    #[serde(default)]
    pub cache_ttl_seconds: Option<i32>,
}

/// `core.SafeBrowsingStats`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SafeBrowsingStatsDto {
    pub cache_hits: i64,
    pub cache_misses: i64,
    pub lookups: i64,
    pub failures: i64,
    pub blocked: i64,
}

impl From<SafeBrowsingStats> for SafeBrowsingStatsDto {
    fn from(stats: SafeBrowsingStats) -> Self {
        Self {
            cache_hits: stats.cache_hits,
            cache_misses: stats.cache_misses,
            lookups: stats.lookups,
            failures: stats.failures,
            blocked: stats.blocked,
        }
    }
}

/// `ipc.SafeBrowsingResponse`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SafeBrowsingResponse {
    pub config: SafeBrowsingConfig,
    pub stats: SafeBrowsingStatsDto,
    #[serde(rename = "blockingIPv4")]
    pub blocking_ipv4: String,
    #[serde(rename = "blockingIPv6")]
    pub blocking_ipv6: String,
    pub block_mode: String,
}

impl AppRuntime {
    /// `GetSafeBrowsing`.
    pub fn safe_browsing_status(&self) -> SafeBrowsingResponse {
        let config = self.config();
        SafeBrowsingResponse {
            config: self.safebrowsing.config(),
            stats: self.safebrowsing.stats().into(),
            // A reputation hit must return the same shape as a rule hit; the UI says so too.
            blocking_ipv4: config.filter.blocking_ipv4,
            blocking_ipv6: config.filter.blocking_ipv6,
            block_mode: config.filter.block_mode,
        }
    }

    /// `ConfigureSafeBrowsing`; the stored value is the normalized one, so a restart reads back
    /// exactly what the engine is using.
    pub fn configure_safe_browsing(
        &self,
        request: ConfigureSafeBrowsingRequest,
    ) -> Result<SafeBrowsingResponse, ControllerError> {
        self.update_config(|config| {
            let mut next = config.safe_browsing.clone();
            if let Some(value) = request.enabled {
                next.enabled = value;
            }
            if let Some(value) = request.parental_enabled {
                next.parental_enabled = value;
            }
            if let Some(value) = request.timeout_ms {
                next.timeout_ms = value;
            }
            if let Some(value) = request.cache_size {
                next.cache_size = value;
            }
            if let Some(value) = request.cache_ttl_seconds {
                next.cache_ttl_seconds = value;
            }
            next.normalize();
            config.safe_browsing = next;
        })
        .map_err(ControllerError::new)?;
        Ok(self.safe_browsing_status())
    }
}
