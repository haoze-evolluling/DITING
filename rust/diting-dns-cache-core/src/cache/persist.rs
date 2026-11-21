use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use crate::wire::ChainTarget;

use super::{now_wall_ms, read_guard, shard_index, write_guard, Cache, Entry};

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

impl Cache {
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
}
