//! The sharded cache container: entries, LRU, TTL deadlines, the background sweeper, statistics
//! and the snapshot projection. This is what `dns_cache.go`, `dns_cache_types.go`,
//! `dns_cache_policy.go` and `dns_cache_snapshot.go` used to implement in Go.
//!
//! Every entry keeps the upstream wire bytes verbatim plus the offsets the wire layer indexed, so
//! a hit is one copy with the query ID and the remaining TTL rewritten — the same cost the Go
//! container paid.
//!
//! Deliberate details copied from the Go implementation instead of "improved":
//!
//! * the shard is chosen by FNV-1a over the key bytes, and a shard holds
//!   `DEFAULT_MAX_ENTRIES / NUM_SHARDS` entries;
//! * a hit promotes its entry at most once per [`LRU_PROMOTE_MS`], so a hot entry does not take
//!   the shard write lock on every query;
//! * an expired entry is dropped lazily by the next lookup and eagerly by the sweep, and only the
//!   sweep counts an expired entry as an eviction;
//! * `update_policy` clears the whole cache when the cache is switched off (a disabled cache is
//!   never read, so its memory is released right away).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::policy::{Config, DEFAULT_MAX_ENTRIES, NUM_SHARDS};
use crate::wire::{self, ChainTarget};

/// Recency update throttle of a hot entry (`lruPromoteInterval` in Go).
pub const LRU_PROMOTE_MS: i64 = 1000;

/// How often the background sweep reclaims entries nobody asked for again (`cleanerInterval`).
pub const SWEEP_INTERVAL: Duration = Duration::from_secs(60);

const RCODE_SUCCESS: u8 = 0;
const RCODE_NAME_ERROR: u8 = 3;

/// One cached answer. `wire` is a copy with the query ID and every indexed TTL rewritten.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hit {
    pub stale: bool,
    pub wire: Vec<u8>,
    pub is_negative: bool,
    pub chain_targets: Vec<ChainTarget>,
    pub ip_list: Vec<String>,
    pub resolved_ips: String,
}

/// Counters the Go layer reports; `entry_count` is walked live, everything else is monotonic.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stats {
    pub enabled: bool,
    pub total_hits: u64,
    pub total_misses: u64,
    pub stale_hits: u64,
    pub negative_hits: u64,
    pub evictions: u64,
    pub entry_count: u32,
    pub max_entries: u32,
}

/// One live entry in the projection the Android layer mirrors into the `dns_cache` table.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SnapshotEntry {
    pub key: Vec<u8>,
    pub query_name: Vec<u8>,
    pub query_type: u16,
    pub query_class: u16,
    pub created_at_ms: i64,
    pub expires_at_ms: i64,
    pub last_hit_at_ms: i64,
    pub hit_count: u64,
    pub original_ttl: u32,
    pub response_size: u32,
}

struct Entry {
    key: Vec<u8>,
    domain: Vec<u8>,
    qtype: u16,
    qclass: u16,
    wire: Vec<u8>,
    ttl_offsets: Vec<u16>,
    original_ttl: u32,
    created_at_ms: i64,
    expires_at_ms: i64,
    expires_at: Instant,
    stale_until: Instant,
    is_negative: bool,
    chain_targets: Vec<ChainTarget>,
    ip_list: Vec<String>,
    resolved_ips: String,
    /// Recency ticket; the shard evicts the smallest one.
    lru_seq: u64,
    hit_count: AtomicU64,
    last_hit_at_ms: AtomicI64,
    /// Set while a stale-while-revalidate refresh is in flight for this entry.
    refreshing: AtomicBool,
}

impl Entry {
    /// Patched copy of the stored answer; `stale` is set by the caller because only the lookup
    /// knows which branch produced it.
    fn hit(&self, query_id: u16, ttl: u32) -> Option<Hit> {
        Some(Hit {
            stale: false,
            wire: wire::patch_response(&self.wire, &self.ttl_offsets, query_id, ttl)?,
            is_negative: self.is_negative,
            chain_targets: self.chain_targets.clone(),
            ip_list: self.ip_list.clone(),
            resolved_ips: self.resolved_ips.clone(),
        })
    }
}

struct Shard {
    entries: HashMap<Vec<u8>, Entry>,
    next_seq: u64,
    max_entries: usize,
}

struct Cleaner {
    stop: Mutex<bool>,
    wake: Condvar,
    thread: Mutex<Option<JoinHandle<()>>>,
}

/// The cache itself; an FFI handle owns one `Arc<Cache>`.
pub struct Cache {
    config: RwLock<Config>,
    shards: Vec<RwLock<Shard>>,
    hits: AtomicU64,
    misses: AtomicU64,
    stale_hits: AtomicU64,
    negative_hits: AtomicU64,
    evictions: AtomicU64,
    cleaner: Arc<Cleaner>,
}

impl Cache {
    /// Builds a cache and starts the background sweeper.
    pub fn new(config: Config) -> Arc<Self> {
        let config = config.normalized();
        let per_shard = (DEFAULT_MAX_ENTRIES / NUM_SHARDS).max(1);
        let shards = (0..NUM_SHARDS)
            .map(|_| {
                RwLock::new(Shard {
                    entries: HashMap::with_capacity(per_shard),
                    next_seq: 0,
                    max_entries: per_shard,
                })
            })
            .collect();
        let cache = Arc::new(Self {
            config: RwLock::new(config),
            shards,
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
            stale_hits: AtomicU64::new(0),
            negative_hits: AtomicU64::new(0),
            evictions: AtomicU64::new(0),
            cleaner: Arc::new(Cleaner {
                stop: Mutex::new(false),
                wake: Condvar::new(),
                thread: Mutex::new(None),
            }),
        });
        Self::start_cleaner(&cache);
        cache
    }

    fn start_cleaner(cache: &Arc<Self>) {
        let cleaner = Arc::clone(&cache.cleaner);
        let weak = Arc::downgrade(cache);
        let spawned = std::thread::Builder::new()
            .name("diting-dns-cache-sweeper".to_string())
            .spawn(move || loop {
                let mut stop = mutex_guard(&cleaner.stop);
                if *stop {
                    return;
                }
                let (guard, _) = cleaner
                    .wake
                    .wait_timeout(stop, SWEEP_INTERVAL)
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                stop = guard;
                if *stop {
                    return;
                }
                drop(stop);
                let Some(cache) = weak.upgrade() else {
                    return;
                };
                cache.sweep_expired(Instant::now());
            });
        if let Ok(handle) = spawned {
            *mutex_guard(&cache.cleaner.thread) = Some(handle);
        }
    }

    /// Stops the background sweeper. Idempotent; the entries stay readable.
    pub fn close(&self) {
        *mutex_guard(&self.cleaner.stop) = true;
        self.cleaner.wake.notify_all();
        let handle = mutex_guard(&self.cleaner.thread).take();
        if let Some(handle) = handle {
            let _ = handle.join();
        }
    }

    /// Replaces the policy. Switching a live cache off releases its entries immediately.
    pub fn update_policy(&self, config: Config) {
        let config = config.normalized();
        let mut guard = write_guard(&self.config);
        let was_enabled = guard.enabled;
        *guard = config;
        let now_enabled = guard.enabled;
        drop(guard);
        if was_enabled && !now_enabled {
            self.clear();
        }
    }

    /// The normalized configuration (used by the FFI layer to report the caller's flags).
    pub fn config(&self) -> Config {
        read_guard(&self.config).clone()
    }

    pub fn clear(&self) {
        for shard in &self.shards {
            let mut guard = write_guard(shard);
            guard.entries.clear();
        }
    }

    /// Looks `query` up. `count == false` is the single-flight re-check: it neither moves the
    /// counters nor the recency, exactly like the old Go `lookup(rawQuery, false)`.
    pub fn get(&self, query: &[u8], count: bool) -> Option<Hit> {
        let config = self.config();
        if !config.enabled || query.len() < 12 {
            return None;
        }
        let (buffer, parts) = build_key(query)?;
        let key = &buffer[..parts.key_len];
        let index = shard_index(key);
        let query_id = u16::from_be_bytes([query[0], query[1]]);
        let now = Instant::now();
        let now_ms = now_wall_ms();

        let mut promote: Option<u64> = None;
        let mut expired: Option<u64> = None;
        let hit = {
            let shard = read_guard(&self.shards[index]);
            match shard.entries.get(key) {
                None => None,
                Some(entry) if now < entry.expires_at => {
                    let mut remaining = entry.expires_at.saturating_duration_since(now).as_secs();
                    if remaining == 0 {
                        remaining = 1;
                    }
                    let mut answer = entry.hit(query_id, remaining as u32)?;
                    answer.stale = false;
                    let previous = entry.last_hit_at_ms.swap(now_ms, Ordering::Relaxed);
                    if now_ms - previous >= LRU_PROMOTE_MS {
                        promote = Some(entry.lru_seq);
                    }
                    if count {
                        entry.hit_count.fetch_add(1, Ordering::Relaxed);
                        if entry.is_negative {
                            self.negative_hits.fetch_add(1, Ordering::Relaxed);
                        }
                    }
                    Some(answer)
                }
                Some(entry) if config.stale_fallback_enabled && now < entry.stale_until => {
                    let mut answer = entry.hit(query_id, 1)?;
                    answer.stale = true;
                    Some(answer)
                }
                Some(entry) => {
                    expired = Some(entry.lru_seq);
                    None
                }
            }
        };

        if let Some(hit) = hit {
            // The counters describe answers the caller actually served: the single-flight
            // re-check (count == false) finds stale entries while refreshing them and must not
            // report a stale hit for that.
            if count {
                if hit.stale {
                    self.stale_hits.fetch_add(1, Ordering::Relaxed);
                } else {
                    self.hits.fetch_add(1, Ordering::Relaxed);
                }
            }
            if let Some(seq) = promote {
                self.promote(index, key, seq);
            }
            return Some(hit);
        }

        if let Some(seq) = expired {
            self.remove_if(index, key, seq);
        }
        if count {
            self.misses.fetch_add(1, Ordering::Relaxed);
        }
        None
    }

    /// Stores one answer; `false` means "this answer must not be cached".
    pub fn put(&self, query: &[u8], response: &[u8]) -> bool {
        if response.len() < 12 {
            return false;
        }
        let config = self.config();
        if !config.enabled {
            return false;
        }
        let Some(meta) = wire::parse_response(response) else {
            return false;
        };
        // A truncated answer carries no complete records; replaying the TC=1 header to later
        // clients would keep them broken even after the upstream recovered.
        if meta.truncated {
            return false;
        }
        let Some((buffer, parts)) = build_key(query) else {
            return false;
        };
        let key = &buffer[..parts.key_len];

        let (is_negative, effective) = if meta.rcode == RCODE_NAME_ERROR
            || (meta.rcode == RCODE_SUCCESS && meta.answer_count == 0)
        {
            if !config.negative_ttl_enabled {
                return false;
            }
            (
                true,
                config.negative_ttl(meta.min_ttl.unwrap_or(0), meta.min_ttl.is_some()),
            )
        } else if meta.rcode == RCODE_SUCCESS && meta.answer_count > 0 {
            (false, config.effective_ttl(meta.min_ttl.unwrap_or(0)))
        } else {
            return false;
        };
        if effective <= 0 {
            return false;
        }

        // With no answers the negative path rewrites the authority TTLs; every other path
        // rewrites the answer TTLs.
        let ttl_offsets = if meta.answer_count == 0 {
            meta.authority_ttl_offsets.clone()
        } else {
            meta.answer_ttl_offsets.clone()
        };

        let now = Instant::now();
        let now_ms = now_wall_ms();
        let expires_at = now + Duration::from_secs(effective as u64);
        let stale_until = if config.stale_fallback_enabled && config.stale_fallback_seconds > 0 {
            expires_at + Duration::from_secs(config.stale_fallback_seconds as u64)
        } else {
            expires_at
        };

        let entry = Entry {
            key: key.to_vec(),
            domain: key[..parts.name_len].to_vec(),
            qtype: parts.qtype,
            qclass: parts.qclass,
            wire: response.to_vec(),
            ttl_offsets,
            original_ttl: meta.min_ttl.unwrap_or(0),
            created_at_ms: now_ms,
            expires_at_ms: now_ms + effective * 1000,
            expires_at,
            stale_until,
            is_negative,
            chain_targets: meta.chain_targets.clone(),
            ip_list: meta.ips.clone(),
            resolved_ips: meta.resolved_ips.clone(),
            lru_seq: 0,
            hit_count: AtomicU64::new(0),
            last_hit_at_ms: AtomicI64::new(now_ms),
            refreshing: AtomicBool::new(false),
        };

        let index = shard_index(key);
        let mut shard = write_guard(&self.shards[index]);
        if shard.entries.contains_key(key) {
            shard.entries.remove(key);
        } else if shard.entries.len() >= shard.max_entries {
            let victim = shard
                .entries
                .iter()
                .min_by_key(|(_, candidate)| candidate.lru_seq)
                .map(|(candidate, _)| candidate.clone());
            if let Some(victim) = victim {
                shard.entries.remove(&victim);
                self.evictions.fetch_add(1, Ordering::Relaxed);
            }
        }
        shard.next_seq += 1;
        let seq = shard.next_seq;
        shard.entries.insert(
            key.to_vec(),
            Entry {
                lru_seq: seq,
                ..entry
            },
        );
        true
    }

    /// Starts the single background refresh of a stale entry; `false` means one is already running
    /// (or the entry is gone), matching the Go `refreshing.CompareAndSwap(false, true)`.
    pub fn refresh_begin(&self, query: &[u8]) -> bool {
        let Some((buffer, parts)) = build_key(query) else {
            return false;
        };
        let key = &buffer[..parts.key_len];
        let shard = read_guard(&self.shards[shard_index(key)]);
        let Some(entry) = shard.entries.get(key) else {
            return false;
        };
        entry
            .refreshing
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
    }

    /// Clears the in-flight marker once the background refresh finished.
    pub fn refresh_done(&self, query: &[u8]) {
        let Some((buffer, parts)) = build_key(query) else {
            return;
        };
        let key = &buffer[..parts.key_len];
        let shard = read_guard(&self.shards[shard_index(key)]);
        if let Some(entry) = shard.entries.get(key) {
            entry.refreshing.store(false, Ordering::Release);
        }
    }

    pub fn stats(&self) -> Stats {
        let entry_count: usize = self
            .shards
            .iter()
            .map(|shard| read_guard(shard).entries.len())
            .sum();
        Stats {
            enabled: read_guard(&self.config).enabled,
            total_hits: self.hits.load(Ordering::Relaxed),
            total_misses: self.misses.load(Ordering::Relaxed),
            stale_hits: self.stale_hits.load(Ordering::Relaxed),
            negative_hits: self.negative_hits.load(Ordering::Relaxed),
            evictions: self.evictions.load(Ordering::Relaxed),
            entry_count: entry_count.min(u32::MAX as usize) as u32,
            max_entries: DEFAULT_MAX_ENTRIES as u32,
        }
    }

    /// Live entries, hottest first, capped at `limit`. Entries past their expiry are skipped: the
    /// engine cannot serve them any more.
    pub fn snapshot(&self, limit: u32) -> Vec<SnapshotEntry> {
        if limit == 0 {
            return Vec::new();
        }
        let now = Instant::now();
        let mut out = Vec::new();
        for shard in &self.shards {
            let guard = read_guard(shard);
            for entry in guard.entries.values() {
                if !(now < entry.expires_at) {
                    continue;
                }
                out.push(SnapshotEntry {
                    key: entry.key.clone(),
                    query_name: entry.domain.clone(),
                    query_type: entry.qtype,
                    query_class: entry.qclass,
                    created_at_ms: entry.created_at_ms,
                    expires_at_ms: entry.expires_at_ms,
                    last_hit_at_ms: entry.last_hit_at_ms.load(Ordering::Relaxed),
                    hit_count: entry.hit_count.load(Ordering::Relaxed),
                    original_ttl: entry.original_ttl,
                    response_size: entry.wire.len().min(u32::MAX as usize) as u32,
                });
            }
        }
        out.sort_unstable_by(|left, right| {
            right
                .hit_count
                .cmp(&left.hit_count)
                .then_with(|| right.expires_at_ms.cmp(&left.expires_at_ms))
        });
        out.truncate(limit as usize);
        out
    }
}

impl Drop for Cache {
    fn drop(&mut self) {
        self.close();
    }
}

fn build_key(query: &[u8]) -> Option<([u8; wire::MAX_KEY_LEN], wire::KeyParts)> {
    if query.len() < 12 {
        return None;
    }
    let mut buffer = [0u8; wire::MAX_KEY_LEN];
    let parts = wire::write_question_key(query, &mut buffer)?;
    Some((buffer, parts))
}

fn shard_index(key: &[u8]) -> usize {
    (fnv32(key) as usize) % NUM_SHARDS
}

/// `fnv32Bytes` in Go: FNV-1a over the key bytes.
fn fnv32(bytes: &[u8]) -> u32 {
    let mut hash = 2166136261u32;
    for &byte in bytes {
        hash ^= u32::from(byte);
        hash = hash.wrapping_mul(16777619);
    }
    hash
}

fn now_wall_ms() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(elapsed) => elapsed.as_millis().min(i64::MAX as u128) as i64,
        Err(_) => 0,
    }
}

fn read_guard<T>(lock: &RwLock<T>) -> RwLockReadGuard<'_, T> {
    lock.read().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn write_guard<T>(lock: &RwLock<T>) -> RwLockWriteGuard<'_, T> {
    lock.write()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn mutex_guard<T>(lock: &Mutex<T>) -> MutexGuard<'_, T> {
    lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

mod maintenance;

#[cfg(test)]
mod tests;
