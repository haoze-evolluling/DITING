//! The prefix-keyed LRU cache.
//!
//! This is `hashCache` from `safebrowsing.go`: entries are keyed by the 2-byte prefix, hold the
//! digests the third party reported for that prefix (possibly none — "not listed" is an answer
//! worth caching) and expire after the configured TTL.
//!
//! The Go version kept a `container/list` next to the map. Here the recency order is a
//! `BTreeMap<stamp, prefix>` with a monotonic counter, which gives the same semantics ("evict the
//! least recently used") without a second allocation per entry and without `VecDeque::retain` on
//! every hit. Expiry is judged against the injected `now_ms`, strictly after the deadline, exactly
//! like `time.Now().After(expiresAt)`.

use std::collections::{BTreeMap, HashMap};

use crate::hash::{hash_prefix, HashPrefix, HostnameHash};

/// `DefaultSafeBrowsingCacheSize`: also the fallback when a configuration asks for 0 entries.
pub const DEFAULT_CACHE_SIZE: usize = 10_000;
/// `DefaultSafeBrowsingCacheTTL` in milliseconds.
pub const DEFAULT_CACHE_TTL_MS: i64 = 600_000;

/// One prefix and the digests reported for it.
struct Entry {
    hashes: Vec<HostnameHash>,
    expires_ms: i64,
    stamp: u64,
}

/// The outcome of [`HashCache::lookup`], shaped like the Go triple
/// `(found, blocked, needQuery)`.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct CacheLookup {
    /// Every prefix had a live entry, so the answer is final.
    pub found: bool,
    /// One of the queried digests is listed. Only meaningful when `found`.
    pub blocked: bool,
    /// Digests whose prefix still has to be asked for (deduped by prefix, in input order).
    pub need_query: Vec<HostnameHash>,
}

/// A prefix-keyed LRU with TTL.
pub struct HashCache {
    /// Capacity after defaulting. `Configure` compares this against the *raw* configured size,
    /// which reproduces the old "rebuild on every Configure when the size is 0" behaviour.
    pub size: usize,
    /// TTL in milliseconds after defaulting.
    pub ttl_ms: i64,
    entries: HashMap<HashPrefix, Entry>,
    order: BTreeMap<u64, HashPrefix>,
    next_stamp: u64,
}

impl HashCache {
    /// `newHashCache`: a non-positive size or TTL falls back to the defaults.
    pub fn new(size: i64, ttl_ms: i64) -> Self {
        let size = if size <= 0 {
            DEFAULT_CACHE_SIZE
        } else {
            size as usize
        };
        let ttl_ms = if ttl_ms <= 0 {
            DEFAULT_CACHE_TTL_MS
        } else {
            ttl_ms
        };
        Self {
            size,
            ttl_ms,
            entries: HashMap::with_capacity(size.min(1024)),
            order: BTreeMap::new(),
            next_stamp: 0,
        }
    }

    /// Number of live entries.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Whether the cache holds nothing.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Checks the digests against the cache.
    ///
    /// All prefixes cached means the answer is final (`found`), and `blocked` says whether one of
    /// the queried digests was reported. Otherwise `need_query` lists what is left to ask; the
    /// hits are still promoted, exactly like the Go loop that walked every digest.
    pub fn lookup(&mut self, hashes: &[HostnameHash], now_ms: i64) -> CacheLookup {
        let mut found = true;
        let mut blocked = false;
        let mut need_query = Vec::new();
        let mut seen: Vec<HashPrefix> = Vec::with_capacity(hashes.len());

        for hash in hashes {
            let prefix = hash_prefix(hash);
            if seen.contains(&prefix) {
                continue;
            }
            seen.push(prefix);

            let Some(entry) = self.entries.get(&prefix) else {
                found = false;
                need_query.push(*hash);
                continue;
            };
            if now_ms > entry.expires_ms {
                self.remove(prefix);
                found = false;
                need_query.push(*hash);
                continue;
            }
            self.touch(prefix);
            if let Some(entry) = self.entries.get(&prefix) {
                if entry.hashes.iter().any(|cached| cached == hash) {
                    blocked = true;
                }
            }
        }

        if !found {
            return CacheLookup {
                found: false,
                blocked: false,
                need_query,
            };
        }
        CacheLookup {
            found: true,
            blocked,
            need_query,
        }
    }

    /// Records the answer for every queried digest's prefix, then evicts past the capacity.
    ///
    /// An empty `received` set is stored too: otherwise the same prefix would be asked for again on
    /// the next query, every time, and never get an answer.
    pub fn store(&mut self, queried: &[HostnameHash], received: &[HostnameHash], now_ms: i64) {
        if queried.is_empty() {
            return;
        }
        let expires_ms = now_ms.saturating_add(self.ttl_ms);
        for hash in queried {
            let prefix = hash_prefix(hash);
            let hits: Vec<HostnameHash> = received
                .iter()
                .filter(|candidate| hash_prefix(candidate) == prefix)
                .copied()
                .collect();

            if self.entries.contains_key(&prefix) {
                self.touch(prefix);
                if let Some(entry) = self.entries.get_mut(&prefix) {
                    entry.hashes = hits;
                    entry.expires_ms = expires_ms;
                }
                continue;
            }

            let stamp = self.next_stamp();
            self.entries.insert(
                prefix,
                Entry {
                    hashes: hits,
                    expires_ms,
                    stamp,
                },
            );
            self.order.insert(stamp, prefix);
        }

        while self.entries.len() > self.size {
            let Some((stamp, prefix)) = self.order.iter().next().map(|(s, p)| (*s, *p)) else {
                break;
            };
            self.order.remove(&stamp);
            self.entries.remove(&prefix);
        }
    }

    fn next_stamp(&mut self) -> u64 {
        self.next_stamp += 1;
        self.next_stamp
    }

    /// Marks a prefix as most recently used.
    fn touch(&mut self, prefix: HashPrefix) {
        let Some(entry) = self.entries.get(&prefix) else {
            return;
        };
        let old_stamp = entry.stamp;
        let stamp = self.next_stamp();
        self.order.remove(&old_stamp);
        self.order.insert(stamp, prefix);
        if let Some(entry) = self.entries.get_mut(&prefix) {
            entry.stamp = stamp;
        }
    }

    fn remove(&mut self, prefix: HashPrefix) {
        if let Some(entry) = self.entries.remove(&prefix) {
            self.order.remove(&entry.stamp);
        }
    }
}

#[cfg(test)]
mod tests;
