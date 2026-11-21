pub mod exclude;
pub mod persist;

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};

use diting_dns_cache_core::policy::{Config as KernelConfig, TtlMode};
use diting_dns_cache_core::{Cache, Hit, SnapshotEntry, Stats};
use diting_dns_wire::build::MessageBuilder;

use crate::resolver::DesktopResolver;
use exclude::CacheExcluder;

pub const DEFAULT_GROUP: &str = "default";
const PREFETCH_THRESHOLD: u64 = 5;
const PREFETCH_BEFORE_MS: i64 = 30_000;
const MAX_PREFETCH_PER_TICK: usize = 64;
const PREFETCH_MIN_INTERVAL_MS: i64 = 5_000;

#[derive(Debug, Clone)]
pub struct CacheSettings {
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
    pub exclude_patterns: Vec<String>,
}

impl Default for CacheSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            max_entries: 4096,
            mode: "limit_max_ttl".to_string(),
            max_ttl_seconds: 3600,
            fixed_ttl_seconds: 3600,
            min_ttl_enabled: true,
            min_ttl_seconds: 60,
            stale_fallback_enabled: true,
            stale_fallback_seconds: 300,
            negative_ttl_enabled: true,
            negative_ttl_seconds: 30,
            optimistic: true,
            prefetch_enabled: false,
            prefetch_threshold: PREFETCH_THRESHOLD as i32,
            prefetch_before_expiry_ms: PREFETCH_BEFORE_MS,
            exclude_patterns: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct CacheMetrics {
    pub stats: Stats,
    pub hit_ratio: f64,
    pub prefetch_count: u64,
}

#[derive(Debug, Clone)]
pub struct CacheEntryItem {
    pub domain: String,
    pub qtype: u16,
    pub qclass: u16,
    pub ttl: i64,
    pub original_ttl: u32,
    pub remaining_ttl: i64,
    pub expires_at: i64,
    pub stale_until: i64,
    pub hit_count: u64,
    pub last_hit_at: i64,
    pub is_negative: bool,
    pub status: &'static str,
}

pub struct DesktopCache {
    cache: Arc<Cache>,
    settings: RwLock<CacheSettings>,
    excluder: RwLock<Arc<CacheExcluder>>,
    prefetch_count: AtomicU64,
    last_prefetch: Mutex<HashMap<Vec<u8>, i64>>,
}

impl DesktopCache {
    pub fn new(settings: CacheSettings) -> Self {
        let (excluder, _) = CacheExcluder::new(&settings.exclude_patterns);
        let cache = Cache::new(kernel_config(&settings));
        cache.set_capacity(capacity(&settings));
        Self {
            cache,
            settings: RwLock::new(settings),
            excluder: RwLock::new(Arc::new(excluder)),
            prefetch_count: AtomicU64::new(0),
            last_prefetch: Mutex::new(HashMap::new()),
        }
    }

    pub fn raw(&self) -> &Arc<Cache> {
        &self.cache
    }

    pub fn settings(&self) -> CacheSettings {
        self.settings
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn configure(&self, settings: CacheSettings) {
        self.cache.update_policy(kernel_config(&settings));
        self.cache.set_capacity(capacity(&settings));
        let (excluder, _) = CacheExcluder::new(&settings.exclude_patterns);
        *self
            .excluder
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Arc::new(excluder);
        *self
            .settings
            .write()
            .unwrap_or_else(|error| error.into_inner()) = settings;
    }

    pub fn is_enabled(&self) -> bool {
        self.cache.config().enabled
    }

    pub fn is_excluded(&self, domain: &str) -> bool {
        self.excluder
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .is_excluded(domain)
    }

    pub fn exclude_hits(&self) -> u64 {
        self.excluder
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .hits()
    }

    pub fn key_for(&self, query: &[u8], group: &str) -> Option<Vec<u8>> {
        let key = diting_dns_wire::question_key(query)?;
        Some(tag_key(&key.key, group))
    }

    pub fn get(&self, query: &[u8], group: &str) -> Option<Hit> {
        if query.len() < 12 {
            return None;
        }
        let key = self.key_for(query, group)?;
        let query_id = u16::from_be_bytes([query[0], query[1]]);
        self.cache.get_keyed(&key, query_id, true)
    }

    pub fn get_without_count(&self, query: &[u8], group: &str) -> Option<Hit> {
        let key = self.key_for(query, group)?;
        let query_id = u16::from_be_bytes([query[0], query[1]]);
        self.cache.get_keyed(&key, query_id, false)
    }

    pub fn put(&self, query: &[u8], response: &[u8], group: &str) -> bool {
        let Some(key) = self.key_for(query, group) else {
            return false;
        };
        let Some((domain, qtype, qclass)) = metadata(query) else {
            return false;
        };
        self.cache
            .put_keyed_meta(&key, &domain, qtype, qclass, response)
    }

    pub fn clear(&self) {
        self.cache.clear();
    }

    pub fn metrics(&self) -> CacheMetrics {
        let stats = self.cache.stats();
        let lookups = stats.total_hits + stats.total_misses;
        CacheMetrics {
            stats,
            hit_ratio: if lookups > 0 {
                stats.total_hits as f64 / lookups as f64
            } else {
                0.0
            },
            prefetch_count: self.prefetch_count.load(Ordering::Relaxed),
        }
    }

    pub fn entries(&self, needle: &str, limit: u32) -> Vec<CacheEntryItem> {
        let needle = needle.trim().to_ascii_lowercase();
        let now = now_ms();
        let mut entries: Vec<CacheEntryItem> = self
            .cache
            .snapshot(limit.max(1))
            .into_iter()
            .map(|entry| project(entry, now))
            .filter(|entry| {
                needle.is_empty()
                    || entry.domain.to_ascii_lowercase().contains(&needle)
                    || qtype_name(entry.qtype)
                        .to_ascii_lowercase()
                        .contains(&needle)
            })
            .collect();
        entries.sort_by_key(|entry| std::cmp::Reverse(entry.hit_count));
        entries.truncate(limit.max(1) as usize);
        entries
    }

    pub fn top_domains(&self, limit: u32) -> Vec<CacheEntryItem> {
        let now = now_ms();
        let mut entries: Vec<CacheEntryItem> = self
            .cache
            .snapshot(0)
            .into_iter()
            .map(|entry| project(entry, now))
            .collect();
        entries.sort_by_key(|entry| std::cmp::Reverse(entry.hit_count));
        entries.truncate(limit.max(1) as usize);
        entries
    }

    pub fn save(&self, path: &std::path::Path) -> Result<persist::PersistStatus, String> {
        persist::save(&self.cache, path)
    }

    pub fn load(&self, path: &std::path::Path) -> Result<usize, String> {
        persist::load(&self.cache, path)
    }

    pub async fn prefetch(&self, resolver: &DesktopResolver) {
        let settings = self.settings();
        if !settings.enabled || !settings.prefetch_enabled {
            return;
        }
        let threshold = if settings.prefetch_threshold > 0 {
            settings.prefetch_threshold as u64
        } else {
            PREFETCH_THRESHOLD
        };
        let before = if settings.prefetch_before_expiry_ms > 0 {
            settings.prefetch_before_expiry_ms
        } else {
            PREFETCH_BEFORE_MS
        };
        let now = now_ms();
        let mut refreshed = 0usize;
        for entry in self.cache.export() {
            if refreshed >= MAX_PREFETCH_PER_TICK {
                break;
            }
            if entry.is_negative || entry.hit_count < threshold {
                continue;
            }
            let remaining = entry.expires_at_ms - now;
            if remaining <= 0 || remaining > before {
                continue;
            }
            {
                let mut guard = self
                    .last_prefetch
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if let Some(last) = guard.get(&entry.key) {
                    if now - *last < PREFETCH_MIN_INTERVAL_MS {
                        continue;
                    }
                }
                guard.insert(entry.key.clone(), now);
            }
            let domain = String::from_utf8_lossy(&entry.domain);
            let Some(query) = MessageBuilder::query(&domain, entry.qtype, entry.qclass).finish()
            else {
                continue;
            };
            if !self.cache.refresh_begin_keyed(&entry.key) {
                continue;
            }
            let _claim = RefreshClaim {
                cache: Arc::clone(&self.cache),
                key: entry.key.clone(),
            };
            let group = group_of_key(&entry.key, &domain, entry.qtype, entry.qclass);
            let result = resolver.resolve(&query, &group).await;
            if let Ok(response) = result {
                self.cache.put_keyed_meta(
                    &entry.key,
                    &entry.domain,
                    entry.qtype,
                    entry.qclass,
                    &response,
                );
                self.prefetch_count.fetch_add(1, Ordering::Relaxed);
                refreshed += 1;
            }
        }
    }
}

struct RefreshClaim {
    cache: Arc<Cache>,
    key: Vec<u8>,
}

impl Drop for RefreshClaim {
    fn drop(&mut self) {
        self.cache.refresh_done_keyed(&self.key);
    }
}

fn kernel_config(settings: &CacheSettings) -> KernelConfig {
    KernelConfig {
        enabled: settings.enabled,
        mode: TtlMode::parse(settings.mode.as_bytes()),
        ttl_scale_percent: 0,
        max_ttl_seconds: settings.max_ttl_seconds,
        fixed_ttl_seconds: settings.fixed_ttl_seconds,
        min_ttl_enabled: settings.min_ttl_enabled,
        min_ttl_seconds: settings.min_ttl_seconds,
        stale_fallback_enabled: settings.stale_fallback_enabled,
        stale_fallback_seconds: settings.stale_fallback_seconds,
        negative_ttl_enabled: settings.negative_ttl_enabled,
        negative_ttl_seconds: settings.negative_ttl_seconds,
    }
}

fn capacity(settings: &CacheSettings) -> usize {
    if settings.max_entries <= 0 {
        4096
    } else {
        settings.max_entries as usize
    }
}

fn tag_key(base: &[u8], group: &str) -> Vec<u8> {
    let group = group.trim();
    if group.is_empty() || group == DEFAULT_GROUP {
        return base.to_vec();
    }
    let mut key = Vec::with_capacity(base.len() + 1 + group.len());
    key.extend_from_slice(base);
    key.push(b':');
    key.extend_from_slice(group.as_bytes());
    key
}

fn metadata(query: &[u8]) -> Option<(Vec<u8>, u16, u16)> {
    let (question, _) = diting_dns_wire::parse_question(query, 12, false)?;
    Some((
        question
            .name
            .trim_end_matches('.')
            .to_ascii_lowercase()
            .into_bytes(),
        question.qtype,
        question.qclass,
    ))
}

fn group_of_key(key: &[u8], domain: &str, qtype: u16, qclass: u16) -> String {
    let base = format!(
        "{}:{qtype}:{qclass}",
        domain.trim_end_matches('.').to_ascii_lowercase()
    );
    let text = String::from_utf8_lossy(key);
    text.strip_prefix(&base)
        .and_then(|rest| rest.strip_prefix(':'))
        .unwrap_or(DEFAULT_GROUP)
        .to_string()
}

fn project(entry: SnapshotEntry, now: i64) -> CacheEntryItem {
    let remaining = (entry.expires_at_ms - now).max(0) / 1000;
    CacheEntryItem {
        domain: String::from_utf8_lossy(&entry.query_name).into_owned(),
        qtype: entry.query_type,
        qclass: entry.query_class,
        ttl: remaining,
        original_ttl: entry.original_ttl,
        remaining_ttl: remaining,
        expires_at: entry.expires_at_ms,
        stale_until: entry.expires_at_ms,
        hit_count: entry.hit_count,
        last_hit_at: entry.last_hit_at_ms,
        is_negative: false,
        status: if entry.expires_at_ms > now {
            "fresh"
        } else {
            "stale"
        },
    }
}

pub fn qtype_name(qtype: u16) -> String {
    match qtype {
        1 => "A".to_string(),
        2 => "NS".to_string(),
        5 => "CNAME".to_string(),
        6 => "SOA".to_string(),
        12 => "PTR".to_string(),
        15 => "MX".to_string(),
        16 => "TXT".to_string(),
        28 => "AAAA".to_string(),
        33 => "SRV".to_string(),
        64 => "SVCB".to_string(),
        65 => "HTTPS".to_string(),
        255 => "ANY".to_string(),
        other => other.to_string(),
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}
