use std::collections::{BTreeMap, HashMap};

use crate::hash::{hash_prefix, HashPrefix, HostnameHash};

pub const DEFAULT_CACHE_SIZE: usize = 10_000;
pub const DEFAULT_CACHE_TTL_MS: i64 = 600_000;

struct Entry {
    hashes: Vec<HostnameHash>,
    expires_ms: i64,
    stamp: u64,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct CacheLookup {
    pub found: bool,
    pub blocked: bool,
    pub need_query: Vec<HostnameHash>,
}

pub struct HashCache {
    pub size: usize,
    pub ttl_ms: i64,
    entries: HashMap<HashPrefix, Entry>,
    order: BTreeMap<u64, HashPrefix>,
    next_stamp: u64,
}

impl HashCache {
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

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

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
