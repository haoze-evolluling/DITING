//! The decision cache, moved out of the Go engine (`android/engine/policy_decision_cache.go`).
//!
//! Go used to sit between the call sites and the kernel: normalize the domain, look the key up in a
//! sharded CLOCK cache, and only on a miss cross the FFI boundary. That split made the Go side keep
//! three things the kernel could own itself: the key dimensions, the eviction policy and the
//! hot-key prewarming after a rule reload. All three live here now; a query is one call.
//!
//! Key: the normalized domain, plus the app name only when the snapshot has app-dependent rules,
//! and the qtype only when some rule carries a `dnsType` constraint. Otherwise all apps and query
//! types share one entry per domain.
//!
//! Eviction: each shard is a fixed ring swept by a CLOCK hand with frequency aging, so a lookup
//! only takes a read lock and bumps atomics; hit counts drive both eviction and prewarm ranking.
//!
//! Reasons: the FFI hands Go a pointer into a cached reason, so every non-empty reason is interned
//! in an append-only pool owned by the cache. Evicting the entry that produced it therefore cannot
//! free the bytes a query is about to copy out; the pool lives exactly as long as the snapshot.

use std::collections::hash_map::RandomState;
use std::collections::HashMap;
use std::hash::{BuildHasher, Hash, Hasher};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, PoisonError, RwLock};

pub(crate) const SHARD_COUNT: usize = 16;
pub(crate) const SHARD_CAPACITY: usize = 512; // 8192 entries in total
pub(crate) const PREWARM_TOP_N: usize = 512;

const BUCKET_COUNT: usize = 1024;
const NO_ENTRY: u32 = u32::MAX;

/// A reason string that can be handed across the FFI boundary.
///
/// Non-empty reasons are interned in the snapshot's cache, so their bytes stay alive until the
/// snapshot is freed even when the entry that produced them has already been evicted.
#[derive(Clone, Default)]
pub struct Reason(Option<Arc<str>>);

impl Reason {
    pub fn empty() -> Reason {
        Reason(None)
    }

    pub fn as_str(&self) -> &str {
        match &self.0 {
            Some(reason) => reason,
            None => "",
        }
    }

    pub fn is_empty(&self) -> bool {
        self.as_str().is_empty()
    }
}

/// One cached key, owned so prewarming can run after the shard's read lock is released.
#[derive(Debug, PartialEq, Eq)]
pub struct Key {
    pub domain: Box<str>,
    pub app: Box<str>,
    pub qtype: u16,
}

impl Key {
    pub fn domain(&self) -> &str {
        &self.domain
    }

    pub fn app(&self) -> &str {
        &self.app
    }

    pub fn qtype(&self) -> u16 {
        self.qtype
    }
}

struct Entry {
    hash: u64,
    domain: Box<str>,
    app: Box<str>,
    qtype: u16,
    blocked: bool,
    reason: Reason,
    hits: AtomicU32,
    referenced: AtomicBool,
    next: u32,
}

struct Shard {
    buckets: [u32; BUCKET_COUNT],
    entries: Vec<Entry>,
    hand: usize,
}

impl Shard {
    fn new() -> Shard {
        Shard {
            buckets: [NO_ENTRY; BUCKET_COUNT],
            entries: Vec::with_capacity(SHARD_CAPACITY),
            hand: 0,
        }
    }

    fn find(&self, hash: u64, domain: &str, app: &str, qtype: u16) -> Option<u32> {
        let mut cursor = self.buckets[bucket_of(hash)];
        while cursor != NO_ENTRY {
            let entry = &self.entries[cursor as usize];
            if entry.hash == hash
                && entry.qtype == qtype
                && entry.app.as_ref() == app
                && entry.domain.as_ref() == domain
            {
                return Some(cursor);
            }
            cursor = entry.next;
        }
        None
    }

    fn link(&mut self, index: u32, entry: &mut Entry) {
        let bucket = bucket_of(entry.hash);
        entry.next = self.buckets[bucket];
        self.buckets[bucket] = index;
    }

    fn unlink(&mut self, hash: u64, victim: u32) {
        let bucket = bucket_of(hash);
        let mut previous = NO_ENTRY;
        let mut cursor = self.buckets[bucket];
        while cursor != NO_ENTRY {
            if cursor == victim {
                let next = self.entries[victim as usize].next;
                if previous == NO_ENTRY {
                    self.buckets[bucket] = next;
                } else {
                    self.entries[previous as usize].next = next;
                }
                return;
            }
            previous = cursor;
            cursor = self.entries[cursor as usize].next;
        }
    }

    fn advance(&mut self) {
        self.hand = (self.hand + 1) % self.entries.len();
    }

    fn insert(&mut self, mut entry: Entry) {
        if self.entries.len() < SHARD_CAPACITY {
            let index = self.entries.len() as u32;
            self.link(index, &mut entry);
            self.entries.push(entry);
            return;
        }
        // CLOCK with frequency aging: a recently used entry gets a second chance, and a
        // frequently used one has its hit count halved instead of being evicted, so a burst of
        // one-off domains cannot flush hot domains.
        loop {
            let victim = self.hand;
            let (referenced, hits) = {
                let entry = &self.entries[victim];
                (
                    entry.referenced.swap(false, Ordering::Relaxed),
                    entry.hits.load(Ordering::Relaxed),
                )
            };
            if referenced {
                self.advance();
                continue;
            }
            if hits >= 2 {
                self.entries[victim].hits.store(hits / 2, Ordering::Relaxed);
                self.advance();
                continue;
            }
            let victim_hash = self.entries[victim].hash;
            self.unlink(victim_hash, victim as u32);
            self.link(victim as u32, &mut entry);
            self.entries[victim] = entry;
            self.advance();
            return;
        }
    }
}

fn bucket_of(hash: u64) -> usize {
    ((hash / SHARD_COUNT as u64) % BUCKET_COUNT as u64) as usize
}

fn read<'a, T>(lock: &'a RwLock<T>) -> std::sync::RwLockReadGuard<'a, T> {
    lock.read().unwrap_or_else(PoisonError::into_inner)
}

fn write<'a, T>(lock: &'a RwLock<T>) -> std::sync::RwLockWriteGuard<'a, T> {
    lock.write().unwrap_or_else(PoisonError::into_inner)
}

/// The per-snapshot cache: sharded CLOCK entries plus the reason pool.
pub struct DecisionCache {
    seed: RandomState,
    app_sensitive: bool,
    qtype_sensitive: bool,
    shards: [RwLock<Shard>; SHARD_COUNT],
    reasons: Mutex<HashMap<Arc<str>, ()>>,
}

impl DecisionCache {
    pub fn new(app_sensitive: bool, qtype_sensitive: bool) -> DecisionCache {
        DecisionCache {
            seed: RandomState::new(),
            app_sensitive,
            qtype_sensitive,
            shards: std::array::from_fn(|_| RwLock::new(Shard::new())),
            reasons: Mutex::new(HashMap::new()),
        }
    }

    /// Folds the dimensions no rule in this snapshot reads, exactly like `cacheKey` did in Go.
    fn effective<'a>(&self, app: &'a str, qtype: u16) -> (&'a str, u16) {
        (
            if self.app_sensitive { app } else { "" },
            if self.qtype_sensitive { qtype } else { 0 },
        )
    }

    fn hash(&self, domain: &str, app: &str, qtype: u16) -> u64 {
        let mut hasher = self.seed.build_hasher();
        domain.hash(&mut hasher);
        app.hash(&mut hasher);
        qtype.hash(&mut hasher);
        hasher.finish()
    }

    /// Interns a reason so the pointer the FFI hands out stays valid for the snapshot's lifetime.
    pub fn intern(&self, reason: &str) -> Reason {
        if reason.is_empty() {
            return Reason::empty();
        }
        let mut pool = self.reasons.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some((existing, _)) = pool.get_key_value(reason) {
            return Reason(Some(existing.clone()));
        }
        let interned: Arc<str> = Arc::from(reason);
        pool.insert(interned.clone(), ());
        Reason(Some(interned))
    }

    pub fn get(&self, domain: &str, app: &str, qtype: u16) -> Option<(bool, Reason)> {
        let (app, qtype) = self.effective(app, qtype);
        let hash = self.hash(domain, app, qtype);
        let shard = &self.shards[(hash % SHARD_COUNT as u64) as usize];
        let guard = read(shard);
        let index = guard.find(hash, domain, app, qtype)?;
        let entry = &guard.entries[index as usize];
        entry.referenced.store(true, Ordering::Relaxed);
        entry.hits.fetch_add(1, Ordering::Relaxed);
        Some((entry.blocked, entry.reason.clone()))
    }

    /// Inserts a verdict when the key is absent. `hits` lets prewarming carry a ranking without
    /// carrying the previous snapshot's counts.
    pub fn put(
        &self,
        domain: &str,
        app: &str,
        qtype: u16,
        blocked: bool,
        reason: Reason,
        hits: u32,
    ) {
        let (app, qtype) = self.effective(app, qtype);
        let hash = self.hash(domain, app, qtype);
        let shard = &self.shards[(hash % SHARD_COUNT as u64) as usize];
        let mut guard = write(shard);
        if guard.find(hash, domain, app, qtype).is_some() {
            return;
        }
        guard.insert(Entry {
            hash,
            domain: domain.into(),
            app: app.into(),
            qtype,
            blocked,
            reason,
            hits: AtomicU32::new(hits),
            referenced: AtomicBool::new(false),
            next: NO_ENTRY,
        });
    }

    /// Up to `limit` keys with the highest hit counts, for prewarming the next snapshot.
    pub fn hottest(&self, limit: usize) -> Vec<Key> {
        let mut ranked: Vec<(u32, Key)> = Vec::new();
        for shard in &self.shards {
            let guard = read(shard);
            for entry in &guard.entries {
                let hits = entry.hits.load(Ordering::Relaxed);
                if hits > 0 {
                    ranked.push((
                        hits,
                        Key {
                            domain: entry.domain.clone(),
                            app: entry.app.clone(),
                            qtype: entry.qtype,
                        },
                    ));
                }
            }
        }
        ranked.sort_by_key(|left| std::cmp::Reverse(left.0));
        ranked.truncate(limit);
        ranked.into_iter().map(|(_, key)| key).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::RuleSnapshot;
    use crate::Snapshot;

    fn snapshot(payload: &str) -> Snapshot {
        let request = RuleSnapshot::parse(payload.as_bytes()).expect("parse payload");
        Snapshot::build(&request)
    }

    fn entry(hash: u64, domain: &str) -> Entry {
        Entry {
            hash,
            domain: domain.into(),
            app: "".into(),
            qtype: 0,
            blocked: true,
            reason: Reason::empty(),
            hits: AtomicU32::new(0),
            referenced: AtomicBool::new(false),
            next: NO_ENTRY,
        }
    }

    #[test]
    fn round_trip_counts_hits() {
        let cache = DecisionCache::new(true, true);
        cache.put(
            "ads.example",
            "com.a",
            1,
            true,
            cache.intern("*.example"),
            0,
        );
        let (blocked, reason) = cache.get("ads.example", "com.a", 1).expect("hit");
        assert!(blocked);
        assert_eq!(reason.as_str(), "*.example");
        assert_eq!(cache.hottest(4).len(), 1);
        // A different app or qtype is a different key.
        assert!(cache.get("ads.example", "com.b", 1).is_none());
        assert!(cache.get("ads.example", "com.a", 28).is_none());
    }

    #[test]
    fn dimensions_fold_when_no_rule_reads_them() {
        let cache = DecisionCache::new(false, false);
        cache.put(
            "ads.example",
            "com.a",
            1,
            true,
            cache.intern("ads.example"),
            1,
        );
        // The app and qtype never reach the key, so every app and qtype hits this entry.
        let (blocked, _) = cache.get("ads.example", "com.b", 28).expect("hit");
        assert!(blocked);
    }

    #[test]
    fn clock_keeps_hot_entries_and_evicts_cold_ones() {
        let mut shard = Shard::new();
        for i in 0..SHARD_CAPACITY {
            shard.insert(entry(i as u64, &format!("d{i}.example")));
        }
        // Make the first entry hot: it survives both the reference bit and the frequency aging.
        for _ in 0..8 {
            let index = shard.find(0, "d0.example", "", 0).expect("present");
            let victim = &shard.entries[index as usize];
            victim.referenced.store(true, Ordering::Relaxed);
            victim.hits.fetch_add(1, Ordering::Relaxed);
        }
        for i in 0..SHARD_CAPACITY * 2 {
            shard.insert(entry(10_000 + i as u64, &format!("n{i}.example")));
        }
        assert!(
            shard.find(0, "d0.example", "", 0).is_some(),
            "frequently used entry must survive CLOCK eviction"
        );
        assert!(shard.find(1, "d1.example", "", 0).is_none());
        assert_eq!(shard.entries.len(), SHARD_CAPACITY);
    }

    #[test]
    fn hottest_ranks_by_hits_and_skips_unused_entries() {
        let cache = DecisionCache::new(false, false);
        cache.put("cold.example", "", 0, false, cache.intern("cold"), 1);
        cache.put("warm.example", "", 0, false, cache.intern("warm"), 3);
        cache.put("hot.example", "", 0, false, cache.intern("hot"), 9);
        // Never looked up: hits stay 0, so it is not a prewarm candidate.
        cache.put("unused.example", "", 0, false, Reason::empty(), 0);
        let hot = cache.hottest(2);
        assert_eq!(hot.len(), 2);
        assert_eq!(hot[0].domain(), "hot.example");
        assert_eq!(hot[1].domain(), "warm.example");
    }

    #[test]
    fn prewarm_rebuilds_hot_keys_against_the_new_snapshot() {
        let prev = snapshot(r#"{"globalBlock":["hot.com"]}"#);
        for _ in 0..20 {
            assert!(prev.answer("hot.com", "", 1).blocked);
        }
        let next = snapshot(r#"{"globalAllow":["hot.com"],"globalBlock":["*.ads.com"]}"#);
        next.prewarm_from(&prev);
        let cache = next.cache().expect("cache");
        let (blocked, reason) = cache.get("hot.com", "", 0).expect("prewarmed");
        assert!(!blocked);
        assert_eq!(reason.as_str(), "__ALLOW__");
    }

    #[test]
    fn concurrent_answers_and_prewarming_stay_coherent() {
        let previous = Arc::new(snapshot(r#"{"globalBlock":["hot.com","*.ads.example"]}"#));
        for _ in 0..64 {
            previous.answer("hot.com", "", 1);
        }
        let next = Arc::new(snapshot(
            r#"{"globalAllow":["hot.com"],"globalBlock":["*.ads.example"]}"#,
        ));
        let workers: Vec<_> = (0..4)
            .map(|_| {
                let next = Arc::clone(&next);
                std::thread::spawn(move || {
                    for i in 0..1000 {
                        let domain = if i % 2 == 0 {
                            "hot.com"
                        } else {
                            "x.ads.example"
                        };
                        let answer = next.answer(domain, "", 1);
                        assert_eq!(answer.blocked, domain.ends_with("ads.example"), "{domain}");
                    }
                })
            })
            .collect();
        // Prewarm races the workers on purpose: it only touches the new snapshot's own cache.
        next.prewarm_from(&previous);
        for worker in workers {
            worker.join().expect("a query thread panicked");
        }
    }

    #[test]
    fn prewarm_skips_a_snapshot_that_reads_other_dimensions() {
        let prev = snapshot(r#"{"globalBlock":["hot.com"]}"#);
        for _ in 0..10 {
            prev.answer("hot.com", "", 1);
        }
        let next = snapshot(
            r#"{"globalBlock":["*.ads.com"],"specialBlock":[{"pattern":"q.com","dnsType":"AAAA"}]}"#,
        );
        next.prewarm_from(&prev);
        assert!(next.cache().expect("cache").get("hot.com", "", 0).is_none());
    }
}
