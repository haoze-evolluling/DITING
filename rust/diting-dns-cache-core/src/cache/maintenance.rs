//! Recency and expiry upkeep split out of `cache.rs`: the hit path only decides *whether* an entry
//! should move, the shard rewrites here, and the sweeper walks the shards without blocking
//! lookups on the idle ones.

use std::time::Instant;

use super::{read_guard, write_guard, Cache};
use std::sync::atomic::Ordering;

impl Cache {
    /// Moves the entry to the front of its shard's recency order. The identity check keeps a
    /// concurrent replacement from being promoted on behalf of the entry the hit saw.
    pub(super) fn promote(&self, index: usize, key: &[u8], seq: u64) {
        let mut shard = write_guard(&self.shards[index]);
        if shard.entries.get(key).map(|entry| entry.lru_seq) != Some(seq) {
            return;
        }
        shard.next_seq += 1;
        let next = shard.next_seq;
        if let Some(entry) = shard.entries.get_mut(key) {
            entry.lru_seq = next;
        }
    }

    /// Drops an entry the lookup found expired, but only if it is still the same entry.
    pub(super) fn remove_if(&self, index: usize, key: &[u8], seq: u64) {
        let mut shard = write_guard(&self.shards[index]);
        let same = shard
            .entries
            .get(key)
            .map(|entry| entry.lru_seq == seq)
            .unwrap_or(false);
        if same {
            shard.entries.remove(key);
        }
    }

    /// Background sweep: an idle shard is only read-locked, a shard with expired entries is
    /// rewritten once and every removed entry counts as an eviction.
    pub(super) fn sweep_expired(&self, now: Instant) {
        for shard in &self.shards {
            {
                let guard = read_guard(shard);
                if !guard.entries.values().any(|entry| now > entry.stale_until) {
                    continue;
                }
            }
            let mut guard = write_guard(shard);
            let mut evicted = 0u64;
            guard.entries.retain(|_, entry| {
                if now > entry.stale_until {
                    evicted += 1;
                    false
                } else {
                    true
                }
            });
            drop(guard);
            if evicted > 0 {
                self.evictions.fetch_add(evicted, Ordering::Relaxed);
            }
        }
    }
}
