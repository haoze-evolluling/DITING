//! Smart DNS cache configuration.

use serde::{Deserialize, Serialize};

use super::serde_util::{is_zero_i64, nullable_vec};

/// Default maximum cache entry count.
pub const DEFAULT_MAX_CACHE_ENTRIES: i32 = 4096;
/// Default cache mode.
pub const CACHE_MODE_LIMIT_MAX_TTL: &str = "limit_max_ttl";

const DEFAULT_MAX_TTL_SECONDS: i64 = 3600;
const DEFAULT_FIXED_TTL_SECONDS: i64 = 3600;
const DEFAULT_MIN_TTL_SECONDS: i64 = 60;
const DEFAULT_STALE_FALLBACK_SECONDS: i64 = 300;
const DEFAULT_NEGATIVE_TTL_SECONDS: i64 = 30;
const DEFAULT_PREFETCH_THRESHOLD: i32 = 5;
const DEFAULT_PREFETCH_BEFORE_EXPIRY_MS: i64 = 30_000;
const MAX_PREFETCH_THRESHOLD: i32 = 100_000;
const MIN_PREFETCH_BEFORE_EXPIRY_MS: i64 = 1_000;
const MAX_PREFETCH_BEFORE_EXPIRY_MS: i64 = 3_600_000;
const DEFAULT_PERSIST_INTERVAL_SECONDS: i64 = 300;
const MIN_PERSIST_INTERVAL_SECONDS: i64 = 30;
const MAX_PERSIST_INTERVAL_SECONDS: i64 = 86_400;

/// Smart cache runtime and policy configuration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct CacheConfig {
    pub enabled: bool,
    pub max_entries: i32,
    pub mode: String,
    pub max_ttl_seconds: i64,
    pub fixed_ttl_seconds: i64,
    pub min_ttl_enabled: bool,
    pub min_ttl_seconds: i64,
    pub stale_fallback_enabled: bool,
    pub stale_fallback_seconds: i64,
    pub negative_ttl_enabled: bool,
    pub negative_ttl_seconds: i64,
    pub optimistic: bool,
    pub prefetch_enabled: bool,
    pub prefetch_threshold: i32,
    pub prefetch_before_expiry_ms: i64,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub exclude_patterns: Vec<String>,
    pub persist_enabled: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub persist_path: String,
    #[serde(skip_serializing_if = "is_zero_i64")]
    pub persist_interval_seconds: i64,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            max_entries: DEFAULT_MAX_CACHE_ENTRIES,
            mode: CACHE_MODE_LIMIT_MAX_TTL.to_string(),
            max_ttl_seconds: DEFAULT_MAX_TTL_SECONDS,
            fixed_ttl_seconds: DEFAULT_FIXED_TTL_SECONDS,
            min_ttl_enabled: true,
            min_ttl_seconds: DEFAULT_MIN_TTL_SECONDS,
            stale_fallback_enabled: true,
            stale_fallback_seconds: DEFAULT_STALE_FALLBACK_SECONDS,
            negative_ttl_enabled: true,
            negative_ttl_seconds: DEFAULT_NEGATIVE_TTL_SECONDS,
            optimistic: true,
            prefetch_enabled: false,
            prefetch_threshold: DEFAULT_PREFETCH_THRESHOLD,
            prefetch_before_expiry_ms: DEFAULT_PREFETCH_BEFORE_EXPIRY_MS,
            exclude_patterns: Vec::new(),
            persist_enabled: false,
            persist_path: String::new(),
            persist_interval_seconds: 0,
        }
    }
}

impl CacheConfig {
    /// Mirror `NormalizeCacheConfig`.
    pub fn normalize(&mut self) {
        if self.max_entries <= 0 {
            self.max_entries = DEFAULT_MAX_CACHE_ENTRIES;
        }
        if self.max_ttl_seconds <= 0 {
            self.max_ttl_seconds = DEFAULT_MAX_TTL_SECONDS;
        }
        if self.fixed_ttl_seconds <= 0 {
            self.fixed_ttl_seconds = DEFAULT_FIXED_TTL_SECONDS;
        }
        if self.min_ttl_seconds <= 0 {
            self.min_ttl_seconds = DEFAULT_MIN_TTL_SECONDS;
        }
        if self.stale_fallback_seconds <= 0 {
            self.stale_fallback_seconds = DEFAULT_STALE_FALLBACK_SECONDS;
        }
        if self.negative_ttl_seconds <= 0 {
            self.negative_ttl_seconds = DEFAULT_NEGATIVE_TTL_SECONDS;
        }
        if self.mode.is_empty() {
            self.mode = CACHE_MODE_LIMIT_MAX_TTL.to_string();
        }
        if self.prefetch_threshold <= 0 {
            self.prefetch_threshold = DEFAULT_PREFETCH_THRESHOLD;
        }
        if self.prefetch_threshold > MAX_PREFETCH_THRESHOLD {
            self.prefetch_threshold = MAX_PREFETCH_THRESHOLD;
        }
        if self.prefetch_before_expiry_ms <= 0 {
            self.prefetch_before_expiry_ms = DEFAULT_PREFETCH_BEFORE_EXPIRY_MS;
        }
        self.prefetch_before_expiry_ms = self
            .prefetch_before_expiry_ms
            .clamp(MIN_PREFETCH_BEFORE_EXPIRY_MS, MAX_PREFETCH_BEFORE_EXPIRY_MS);

        // Persist parameters are only filled when persistence is explicitly enabled; otherwise a
        // positive interval would look configured while nothing is written.
        if self.persist_enabled {
            if self.persist_interval_seconds <= 0 {
                self.persist_interval_seconds = DEFAULT_PERSIST_INTERVAL_SECONDS;
            }
            self.persist_interval_seconds = self
                .persist_interval_seconds
                .clamp(MIN_PERSIST_INTERVAL_SECONDS, MAX_PERSIST_INTERVAL_SECONDS);
        } else if self.persist_interval_seconds < 0 {
            self.persist_interval_seconds = 0;
        }
    }
}
