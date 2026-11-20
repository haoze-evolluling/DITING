use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::policy::{Config, DEFAULT_MAX_ENTRIES, NUM_SHARDS};
use crate::wire::{self, ChainTarget};

pub const LRU_PROMOTE_MS: i64 = 1000;

pub const SWEEP_INTERVAL: Duration = Duration::from_secs(60);

const RCODE_SUCCESS: u8 = 0;
const RCODE_NAME_ERROR: u8 = 3;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hit {
    pub stale: bool,
    pub wire: Vec<u8>,
    pub is_negative: bool,
    pub chain_targets: Vec<ChainTarget>,
    pub ip_list: Vec<String>,
    pub resolved_ips: String,
}

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PersistEntry {
    pub key: Vec<u8>,
    pub domain: Vec<u8>,
    pub qtype: u16,
    pub qclass: u16,
    pub wire: Vec<u8>,
    pub ttl_offsets: Vec<u16>,
    pub original_ttl: u32,
    pub created_at_ms: i64,
    pub expires_at_ms: i64,
    pub stale_until_ms: i64,
    pub is_negative: bool,
    pub chain_targets: Vec<ChainTarget>,
    pub ip_list: Vec<String>,
    pub resolved_ips: String,
    pub hit_count: u64,
    pub last_hit_at_ms: i64,
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
    lru_seq: u64,
    hit_count: AtomicU64,
    last_hit_at_ms: AtomicI64,
    refreshing: AtomicBool,
}

impl Entry {
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

pub struct Cache {
    config: RwLock<Config>,
    shards: Vec<RwLock<Shard>>,
    capacity: AtomicUsize,
    hits: AtomicU64,
    misses: AtomicU64,
    stale_hits: AtomicU64,
    negative_hits: AtomicU64,
    evictions: AtomicU64,
    cleaner: Arc<Cleaner>,
}

impl Cache {
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
            capacity: AtomicUsize::new(DEFAULT_MAX_ENTRIES),
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

    pub fn close(&self) {
        *mutex_guard(&self.cleaner.stop) = true;
        self.cleaner.wake.notify_all();
        let handle = mutex_guard(&self.cleaner.thread).take();
        if let Some(handle) = handle {
            if handle.thread().id() == std::thread::current().id() {
                return;
            }
            let _ = handle.join();
        }
    }

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

    pub fn config(&self) -> Config {
        read_guard(&self.config).clone()
    }

    pub fn clear(&self) {
        for shard in &self.shards {
            let mut guard = write_guard(shard);
            guard.entries.clear();
        }
    }

    pub fn get(&self, query: &[u8], count: bool) -> Option<Hit> {
        let config = self.config();
        if !config.enabled || query.len() < 12 {
            return None;
        }
        let (buffer, parts) = build_key(query)?;
        let query_id = u16::from_be_bytes([query[0], query[1]]);
        self.get_keyed(&buffer[..parts.key_len], query_id, count)
    }

    pub fn get_keyed(&self, key: &[u8], query_id: u16, count: bool) -> Option<Hit> {
        let config = self.config();
        if !config.enabled || key.is_empty() {
            return None;
        }
        let index = shard_index(key);
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

    pub fn put(&self, query: &[u8], response: &[u8]) -> bool {
        let Some((buffer, parts)) = build_key(query) else {
            return false;
        };
        self.put_keyed(&buffer[..parts.key_len], response)
    }

    pub fn put_keyed(&self, key: &[u8], response: &[u8]) -> bool {
        let Some((domain, qtype, qclass)) = parse_key_parts(key) else {
            return false;
        };
        self.put_keyed_meta(key, &domain, qtype, qclass, response)
    }

    pub fn put_keyed_meta(
        &self,
        key: &[u8],
        domain: &[u8],
        qtype: u16,
        qclass: u16,
        response: &[u8],
    ) -> bool {
        if response.len() < 12 || key.is_empty() {
            return false;
        }
        let config = self.config();
        if !config.enabled {
            return false;
        }
        let Some(meta) = wire::parse_response(response) else {
            return false;
        };
        if meta.truncated {
            return false;
        }
        let domain = domain.to_vec();

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
            domain,
            qtype,
            qclass,
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

    pub fn refresh_begin(&self, query: &[u8]) -> bool {
        let Some((buffer, parts)) = build_key(query) else {
            return false;
        };
        self.refresh_begin_keyed(&buffer[..parts.key_len])
    }

    pub fn refresh_begin_keyed(&self, key: &[u8]) -> bool {
        let shard = read_guard(&self.shards[shard_index(key)]);
        let Some(entry) = shard.entries.get(key) else {
            return false;
        };
        entry
            .refreshing
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
    }

    pub fn refresh_done(&self, query: &[u8]) {
        let Some((buffer, parts)) = build_key(query) else {
            return;
        };
        self.refresh_done_keyed(&buffer[..parts.key_len]);
    }

    pub fn refresh_done_keyed(&self, key: &[u8]) {
        let shard = read_guard(&self.shards[shard_index(key)]);
        if let Some(entry) = shard.entries.get(key) {
            entry.refreshing.store(false, Ordering::Release);
        }
    }

    pub fn remove_keyed(&self, key: &[u8]) -> bool {
        let mut shard = write_guard(&self.shards[shard_index(key)]);
        shard.entries.remove(key).is_some()
    }

    pub fn set_capacity(&self, max_entries: usize) {
        let max_entries = if max_entries == 0 {
            DEFAULT_MAX_ENTRIES
        } else {
            max_entries.max(NUM_SHARDS)
        };
        self.capacity.store(max_entries, Ordering::Relaxed);
        let per_shard = (max_entries / NUM_SHARDS).max(1);
        for shard in &self.shards {
            let mut guard = write_guard(shard);
            guard.max_entries = per_shard;
            while guard.entries.len() > per_shard {
                let victim = guard
                    .entries
                    .iter()
                    .min_by_key(|(_, entry)| entry.lru_seq)
                    .map(|(key, _)| key.clone());
                let Some(victim) = victim else {
                    break;
                };
                guard.entries.remove(&victim);
                self.evictions.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    pub fn capacity(&self) -> usize {
        self.capacity.load(Ordering::Relaxed)
    }

    pub fn export(&self) -> Vec<PersistEntry> {
        let now = Instant::now();
        let now_ms = now_wall_ms();
        let mut out = Vec::new();
        for shard in &self.shards {
            let guard = read_guard(shard);
            for entry in guard.entries.values() {
                if entry.stale_until <= now {
                    continue;
                }
                out.push(PersistEntry {
                    key: entry.key.clone(),
                    domain: entry.domain.clone(),
                    qtype: entry.qtype,
                    qclass: entry.qclass,
                    wire: entry.wire.clone(),
                    ttl_offsets: entry.ttl_offsets.clone(),
                    original_ttl: entry.original_ttl,
                    created_at_ms: entry.created_at_ms,
                    expires_at_ms: entry.expires_at_ms,
                    stale_until_ms: now_ms
                        + entry
                            .stale_until
                            .saturating_duration_since(now)
                            .as_millis()
                            .min(i64::MAX as u128) as i64,
                    is_negative: entry.is_negative,
                    chain_targets: entry.chain_targets.clone(),
                    ip_list: entry.ip_list.clone(),
                    resolved_ips: entry.resolved_ips.clone(),
                    hit_count: entry.hit_count.load(Ordering::Relaxed),
                    last_hit_at_ms: entry.last_hit_at_ms.load(Ordering::Relaxed),
                });
            }
        }
        out
    }

    pub fn import(&self, entries: Vec<PersistEntry>) -> usize {
        let now = Instant::now();
        let now_ms = now_wall_ms();
        let mut restored = 0usize;
        for entry in entries {
            if entry.key.is_empty() || entry.wire.len() < 12 || entry.stale_until_ms <= now_ms {
                continue;
            }
            let expires_at = now
                + Duration::from_millis(entry.expires_at_ms.saturating_sub(now_ms).max(1) as u64);
            let stale_until = now
                + Duration::from_millis(entry.stale_until_ms.saturating_sub(now_ms).max(1) as u64);
            let restored_entry = Entry {
                key: entry.key.clone(),
                domain: entry.domain,
                qtype: entry.qtype,
                qclass: entry.qclass,
                wire: entry.wire,
                ttl_offsets: entry.ttl_offsets,
                original_ttl: entry.original_ttl,
                created_at_ms: entry.created_at_ms,
                expires_at_ms: entry.expires_at_ms,
                expires_at,
                stale_until,
                is_negative: entry.is_negative,
                chain_targets: entry.chain_targets,
                ip_list: entry.ip_list,
                resolved_ips: entry.resolved_ips,
                lru_seq: 0,
                hit_count: AtomicU64::new(entry.hit_count),
                last_hit_at_ms: AtomicI64::new(entry.last_hit_at_ms),
                refreshing: AtomicBool::new(false),
            };
            let index = shard_index(&restored_entry.key);
            let mut shard = write_guard(&self.shards[index]);
            if shard.entries.contains_key(&restored_entry.key) {
                shard.entries.remove(&restored_entry.key);
            } else if shard.entries.len() >= shard.max_entries {
                let victim = shard
                    .entries
                    .iter()
                    .min_by_key(|(_, candidate)| candidate.lru_seq)
                    .map(|(key, _)| key.clone());
                if let Some(victim) = victim {
                    shard.entries.remove(&victim);
                    self.evictions.fetch_add(1, Ordering::Relaxed);
                }
            }
            shard.next_seq += 1;
            let seq = shard.next_seq;
            shard.entries.insert(
                restored_entry.key.clone(),
                Entry {
                    lru_seq: seq,
                    ..restored_entry
                },
            );
            restored += 1;
        }
        restored
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
            max_entries: self.capacity().min(u32::MAX as usize) as u32,
        }
    }

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

fn parse_key_parts(key: &[u8]) -> Option<(Vec<u8>, u16, u16)> {
    let last = key.iter().rposition(|byte| *byte == b':')?;
    let previous = key[..last].iter().rposition(|byte| *byte == b':')?;
    let qclass = parse_decimal(&key[last + 1..])?;
    let qtype = parse_decimal(&key[previous + 1..last])?;
    Some((key[..previous].to_vec(), qtype, qclass))
}

fn parse_decimal(bytes: &[u8]) -> Option<u16> {
    if bytes.is_empty() || bytes.len() > 5 {
        return None;
    }
    let mut value = 0u32;
    for byte in bytes {
        if !byte.is_ascii_digit() {
            return None;
        }
        value = value * 10 + u32::from(byte - b'0');
    }
    u16::try_from(value).ok()
}

fn shard_index(key: &[u8]) -> usize {
    (fnv32(key) as usize) % NUM_SHARDS
}

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
