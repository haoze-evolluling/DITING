//! Safe Browsing / parental-control facade.
//!
//! The kernel (`diting-safebrowsing-core`) owns the hash caches and the verdict; this facade owns
//! the configuration, the counters the API reports and the lock discipline the DNS hot path needs.
//! The asynchronous TXT lookup stays in the DNS stage, which is the only layer allowed to talk to
//! an upstream resolver.

use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use diting_desktop_api::config::security::SafeBrowsingConfig;
use diting_safebrowsing_core::engine::Engine;

/// Cumulative counters, mirroring `core.SafeBrowsingStats`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SafeBrowsingStats {
    pub cache_hits: i64,
    pub cache_misses: i64,
    pub lookups: i64,
    pub failures: i64,
    pub blocked: i64,
}

/// Shared reputation engine used by the DNS stage and the management API.
pub struct SafeBrowsingEngine {
    config: RwLock<SafeBrowsingConfig>,
    engine: Engine,
    cache_hits: AtomicI64,
    cache_misses: AtomicI64,
    lookups: AtomicI64,
    failures: AtomicI64,
    blocked: AtomicI64,
}

impl SafeBrowsingEngine {
    pub fn new(config: SafeBrowsingConfig) -> Self {
        let engine = Engine::new(cache_size(&config), cache_ttl_ms(&config));
        Self {
            config: RwLock::new(config),
            engine,
            cache_hits: AtomicI64::new(0),
            cache_misses: AtomicI64::new(0),
            lookups: AtomicI64::new(0),
            failures: AtomicI64::new(0),
            blocked: AtomicI64::new(0),
        }
    }

    /// Applies a new configuration. The kernel rebuilds its caches only when size or TTL changed.
    pub fn configure(&self, config: SafeBrowsingConfig) {
        self.engine
            .configure(cache_size(&config), cache_ttl_ms(&config));
        *self.write() = config;
    }

    pub fn config(&self) -> SafeBrowsingConfig {
        self.read().clone()
    }

    pub fn engine(&self) -> &Engine {
        &self.engine
    }

    /// Records one verdict. `from_cache` and `blocked` are independent facts.
    pub fn record(&self, from_cache: bool, blocked: bool) {
        if from_cache {
            self.cache_hits.fetch_add(1, Ordering::Relaxed);
        } else {
            self.cache_misses.fetch_add(1, Ordering::Relaxed);
        }
        self.lookups.fetch_add(1, Ordering::Relaxed);
        if blocked {
            self.blocked.fetch_add(1, Ordering::Relaxed);
        }
    }

    /// Records a lookup that could not be completed (timeout, transport error, bad response).
    pub fn record_failure(&self) {
        self.failures.fetch_add(1, Ordering::Relaxed);
    }

    pub fn stats(&self) -> SafeBrowsingStats {
        SafeBrowsingStats {
            cache_hits: self.cache_hits.load(Ordering::Relaxed),
            cache_misses: self.cache_misses.load(Ordering::Relaxed),
            lookups: self.lookups.load(Ordering::Relaxed),
            failures: self.failures.load(Ordering::Relaxed),
            blocked: self.blocked.load(Ordering::Relaxed),
        }
    }

    fn read(&self) -> RwLockReadGuard<'_, SafeBrowsingConfig> {
        self.config
            .read()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, SafeBrowsingConfig> {
        self.config
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

fn cache_size(config: &SafeBrowsingConfig) -> i64 {
    i64::from(config.cache_size.max(0))
}

fn cache_ttl_ms(config: &SafeBrowsingConfig) -> i64 {
    i64::from(config.cache_ttl_seconds) * 1000
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counters_are_independent() {
        let engine = SafeBrowsingEngine::new(SafeBrowsingConfig::default());
        engine.record(true, false);
        engine.record(false, true);
        engine.record_failure();
        let stats = engine.stats();
        assert_eq!(stats.cache_hits, 1);
        assert_eq!(stats.cache_misses, 1);
        assert_eq!(stats.lookups, 2);
        assert_eq!(stats.blocked, 1);
        assert_eq!(stats.failures, 1);
    }

    #[test]
    fn configure_updates_the_snapshot() {
        let engine = SafeBrowsingEngine::new(SafeBrowsingConfig::default());
        let mut config = engine.config();
        config.enabled = true;
        config.cache_size = 32;
        engine.configure(config.clone());
        assert!(engine.config().enabled);
        assert_eq!(engine.config().cache_size, 32);
    }
}
