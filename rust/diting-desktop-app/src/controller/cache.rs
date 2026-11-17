//! Cache inspection and configuration (`/api/v1/cache/*`).

use serde::{Deserialize, Serialize};

use diting_desktop_api::config::CacheConfig;
use diting_desktop_core::cache::CacheEntryItem;

use crate::controller::ControllerError;
use crate::AppRuntime;

/// `core.CacheStats` wire shape.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CacheStats {
    pub enabled: bool,
    pub total_hits: u64,
    pub total_misses: u64,
    pub stale_hits: u64,
    pub negative_hits: u64,
    pub hit_ratio: f64,
    pub entry_count: i32,
    pub max_entries: i32,
    pub eviction_count: u64,
    pub prefetch_count: u64,
}

/// `core.CacheEntryItem` wire shape.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CacheEntry {
    pub domain: String,
    pub qtype: String,
    pub ttl: u32,
    pub original_ttl: u32,
    pub remaining_ttl: i64,
    pub expires_at: i64,
    pub stale_until: i64,
    pub hit_count: u64,
    pub last_hit_at: i64,
    pub is_negative: bool,
    pub status: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub ip_list: Vec<String>,
}

/// `core.CacheDomainStat` wire shape.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CacheDomainStat {
    pub domain: String,
    pub qtype: String,
    pub hit_count: u64,
    pub last_hit_at: i64,
}

/// `CacheEntriesResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CacheEntriesResponse {
    pub total: i32,
    pub entries: Vec<CacheEntry>,
}

/// `CachePersistResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CachePersistResponse {
    pub path: String,
    #[serde(skip_serializing_if = "is_zero")]
    pub restored: i32,
    pub entry_count: i32,
    pub persist_on: bool,
    pub interval_sec: i64,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub last_error: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub exclude_rules: Vec<String>,
    pub exclude_hits: u64,
}

fn is_zero(value: &i32) -> bool {
    *value == 0
}

fn project(item: &CacheEntryItem) -> CacheEntry {
    CacheEntry {
        domain: item.domain.clone(),
        qtype: diting_desktop_core::cache::qtype_name(item.qtype),
        ttl: item.ttl.max(0) as u32,
        original_ttl: item.original_ttl,
        remaining_ttl: item.remaining_ttl,
        expires_at: item.expires_at,
        stale_until: item.stale_until,
        hit_count: item.hit_count,
        last_hit_at: item.last_hit_at,
        is_negative: item.is_negative,
        status: item.status.to_string(),
        ip_list: Vec::new(),
    }
}

impl AppRuntime {
    /// `GetCacheStats`.
    pub fn cache_stats(&self) -> CacheStats {
        let metrics = self.cache.metrics();
        let stats = metrics.stats;
        let settings = self.cache.settings();
        CacheStats {
            enabled: settings.enabled,
            total_hits: stats.total_hits,
            total_misses: stats.total_misses,
            stale_hits: stats.stale_hits,
            negative_hits: stats.negative_hits,
            hit_ratio: metrics.hit_ratio,
            entry_count: stats.entry_count as i32,
            max_entries: stats.max_entries as i32,
            eviction_count: stats.evictions,
            prefetch_count: metrics.prefetch_count,
        }
    }

    /// `GetCacheEntries`. `total` mirrors the number of entries scanned before the limit.
    pub fn cache_entries(&self, query: &str, limit: i32) -> CacheEntriesResponse {
        let limit = limit.max(1);
        let entries: Vec<CacheEntry> = self
            .cache
            .entries(query, limit as u32)
            .iter()
            .map(project)
            .collect();
        CacheEntriesResponse {
            total: entries.len() as i32,
            entries,
        }
    }

    /// `GetCacheTopDomains`.
    pub fn cache_top_domains(&self, limit: i32) -> Vec<CacheDomainStat> {
        self.cache
            .top_domains(limit.max(1) as u32)
            .iter()
            .map(|item| CacheDomainStat {
                domain: item.domain.clone(),
                qtype: diting_desktop_core::cache::qtype_name(item.qtype),
                hit_count: item.hit_count,
                last_hit_at: item.last_hit_at,
            })
            .collect()
    }

    /// `ClearCache`.
    pub fn clear_cache(&self) -> Result<(), ControllerError> {
        self.cache.clear();
        Ok(())
    }

    /// `GetCacheConfig`.
    pub fn cache_config(&self) -> CacheConfig {
        self.config().cache
    }

    fn cache_persist_path(&self, config: &CacheConfig) -> String {
        if config.persist_path.trim().is_empty() {
            diting_desktop_platform::paths::default_data_dir()
                .join("cache.json")
                .to_string_lossy()
                .into_owned()
        } else {
            config.persist_path.clone()
        }
    }

    /// `UpdateCacheConfig`.
    pub fn update_cache_config(&self, mut config: CacheConfig) -> Result<(), ControllerError> {
        config.normalize();
        if config.persist_enabled && config.persist_path.trim().is_empty() {
            config.persist_path = self.cache_persist_path(&config);
        }
        self.update_config(|next| next.cache = config)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    /// `CachePersistStatus`.
    pub fn cache_persist_status(&self) -> CachePersistResponse {
        let config = self.config();
        let stats = self.cache_stats();
        CachePersistResponse {
            path: self.cache_persist_path(&config.cache),
            restored: 0,
            entry_count: stats.entry_count,
            persist_on: config.cache.persist_enabled,
            interval_sec: config.cache.persist_interval_seconds,
            last_error: String::new(),
            exclude_rules: config.cache.exclude_patterns.clone(),
            exclude_hits: self.cache.exclude_hits(),
        }
    }

    /// `DumpCache`.
    pub fn dump_cache(&self) -> Result<CachePersistResponse, ControllerError> {
        let config = self.config();
        let path = std::path::PathBuf::from(self.cache_persist_path(&config.cache));
        self.cache.save(&path).map_err(ControllerError::new)?;
        Ok(self.cache_persist_status())
    }

    /// `LoadCache`.
    pub fn load_cache_from_disk(&self) -> Result<CachePersistResponse, ControllerError> {
        let config = self.config();
        let path = std::path::PathBuf::from(self.cache_persist_path(&config.cache));
        let restored = self.cache.load(&path).map_err(ControllerError::new)?;
        let mut status = self.cache_persist_status();
        status.restored = restored as i32;
        Ok(status)
    }
}
