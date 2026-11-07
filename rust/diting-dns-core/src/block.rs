//! Dynamic block escalation: port of `dynamicBlockTracker` in `android/engine/dns_config.go`.
//!
//! Per domain, a request counter inside a window; once the count exceeds the threshold the domain
//! is answered with NXDOMAIN for a while, and everything below the threshold is NODATA. Disabling
//! the feature passes the configured mode through untouched and records nothing.
//!
//! The response numbers are Go's `ResponseType` values (`ResponseCustomIP` 0, `ResponseNXDomain` 1,
//! `ResponseRefused` 2, `ResponseNoData` 3); the kernel never interprets the fallback, it only
//! echoes it back when the feature is off.
//!
//! Go read `time.Now()` inside the tracker; here `now_ns` is a parameter, so a scripted clock
//! replays exactly (`tests/fixtures/blocks_trace.tsv`).

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

/// `ResponseCustomIP`: the configured mode, answered with a synthetic `0.0.0.0` / `::` record.
pub const RESPONSE_CUSTOM_IP: u32 = 0;
/// `ResponseNXDomain`.
pub const RESPONSE_NX_DOMAIN: u32 = 1;
/// `ResponseRefused`.
pub const RESPONSE_REFUSED: u32 = 2;
/// `ResponseNoData`: the "below the threshold" answer while escalation is enabled.
pub const RESPONSE_NO_DATA: u32 = 3;

/// `len(t.entries) > 4096` drops one arbitrary entry (Go ranged over the map; which one is
/// unspecified there too, only the bound is observable).
pub const MAX_ENTRIES: usize = 4096;

/// The subset of `dynamicBlockConfig` the tracker reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BlockConfig {
    pub enabled: bool,
    pub request_threshold: u32,
    pub window_ns: i64,
    pub nx_domain_ns: i64,
}

#[derive(Debug, Clone, Copy)]
struct Entry {
    window_started_ns: i64,
    request_count: u32,
    nx_domain_until_ns: i64,
}

/// The per-domain state of one engine.
pub struct DynamicBlocks {
    entries: Mutex<HashMap<String, Entry>>,
}

impl Default for DynamicBlocks {
    fn default() -> Self {
        Self::new()
    }
}

impl DynamicBlocks {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    /// `reset`: called when a new DNS config snapshot is applied.
    pub fn reset(&self) {
        self.lock().clear();
    }

    /// `responseFor`: the block response mode for one freshly blocked query.
    ///
    /// `domain` is already normalized (trimmed, lowercased, trailing dot removed) by the caller,
    /// exactly as `effectiveBlockResponseType` did before this moved.
    pub fn response_for(
        &self,
        domain: &str,
        config: &BlockConfig,
        fallback: u32,
        now_ns: i64,
    ) -> u32 {
        if !config.enabled {
            return fallback;
        }

        let mut entries = self.lock();
        if let Some(entry) = entries.get(domain) {
            // `now.Before(entry.nxDomainUntil)`: the hold wins over the window logic.
            if now_ns < entry.nx_domain_until_ns {
                return RESPONSE_NX_DOMAIN;
            }
        }

        // `now.Sub(entry.windowStarted) >= window` starts a fresh window; a missing entry starts
        // one too.
        let mut entry = match entries.get(domain) {
            Some(existing)
                if now_ns.saturating_sub(existing.window_started_ns) < config.window_ns =>
            {
                Entry {
                    window_started_ns: existing.window_started_ns,
                    request_count: existing.request_count.saturating_add(1),
                    nx_domain_until_ns: existing.nx_domain_until_ns,
                }
            }
            _ => Entry {
                window_started_ns: now_ns,
                request_count: 1,
                nx_domain_until_ns: 0,
            },
        };

        let escalated = entry.request_count > config.request_threshold;
        if escalated {
            entry.nx_domain_until_ns = now_ns.saturating_add(config.nx_domain_ns);
        }
        entries.insert(domain.to_string(), entry);

        if escalated {
            // The old implementation returns before the eviction check on this path.
            return RESPONSE_NX_DOMAIN;
        }
        if entries.len() > MAX_ENTRIES {
            if let Some(key) = entries.keys().next().cloned() {
                entries.remove(&key);
            }
        }
        RESPONSE_NO_DATA
    }

    /// Number of tracked domains; the tests use it to pin the eviction bound.
    pub fn len(&self) -> usize {
        self.lock().len()
    }

    /// Whether any domain is tracked.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<String, Entry>> {
        self.entries
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

#[cfg(test)]
mod tests;
