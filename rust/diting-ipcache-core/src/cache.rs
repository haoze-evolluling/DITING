//! The LRU itself: `ip_domain_cache.go`'s map + list, with a stamp-ordered eviction.

use std::collections::{BTreeMap, HashMap};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

/// `newIPDomainCache`'s default when the caller passes a non-positive size.
pub const DEFAULT_MAX_SIZE: usize = 2048;

struct Entry {
    domain: String,
    /// Monotonic stamp of the last `put`; the smallest stamp is evicted first.
    stamp: u128,
}

struct State {
    entries: HashMap<String, Entry>,
    order: BTreeMap<u128, String>,
    next_stamp: u128,
    max_size: usize,
}

/// One engine's IP → domain cache.
pub struct IpDomainCache {
    state: RwLock<State>,
}

impl IpDomainCache {
    /// `newIPDomainCache`: a non-positive `max_size` falls back to 2048.
    pub fn new(max_size: i32) -> Self {
        let max_size = if max_size <= 0 {
            DEFAULT_MAX_SIZE
        } else {
            max_size as usize
        };
        Self {
            state: RwLock::new(State {
                entries: HashMap::with_capacity(max_size),
                order: BTreeMap::new(),
                next_stamp: 0,
                max_size,
            }),
        }
    }

    /// `put`: ignore empty keys, update in place + touch an existing key, otherwise insert and
    /// evict the least-recently-written key when at capacity.
    pub fn put(&self, ip: &str, domain: &str) {
        if ip.is_empty() || domain.is_empty() {
            return;
        }
        let mut state = self.write();
        let stamp = state.next_stamp;
        state.next_stamp = state.next_stamp.wrapping_add(1);

        if let Some(entry) = state.entries.get_mut(ip) {
            entry.domain = domain.to_string();
            let old_stamp = entry.stamp;
            entry.stamp = stamp;
            state.order.remove(&old_stamp);
            state.order.insert(stamp, ip.to_string());
            return;
        }

        if state.entries.len() >= state.max_size {
            if let Some(oldest_stamp) = state.order.keys().next().copied() {
                if let Some(evicted_ip) = state.order.remove(&oldest_stamp) {
                    state.entries.remove(&evicted_ip);
                }
            }
        }

        state.entries.insert(
            ip.to_string(),
            Entry {
                domain: domain.to_string(),
                stamp,
            },
        );
        state.order.insert(stamp, ip.to_string());
    }

    /// `get`: a read never touches the order.
    pub fn get(&self, ip: &str) -> Option<String> {
        if ip.is_empty() {
            return None;
        }
        self.read()
            .entries
            .get(ip)
            .map(|entry| entry.domain.clone())
    }

    /// Current entry count (test/telemetry helper).
    pub fn len(&self) -> u32 {
        self.read().entries.len() as u32
    }

    /// Whether the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn read(&self) -> RwLockReadGuard<'_, State> {
        self.state.read().unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

#[cfg(test)]
mod tests;
