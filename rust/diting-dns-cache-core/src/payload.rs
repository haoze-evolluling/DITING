//! The binary layouts the container shares with `android/engine/dns_cache_native*.go`.
//!
//! Everything is little endian and every payload starts with a layout byte, so a mismatched
//! Go/Rust pair is a loud rejection instead of a misread field. `bytes` is a `u32` length
//! followed by raw bytes (names are wire-decoded byte strings, not necessarily UTF-8); `text` is
//! the same shape with a UTF-8 guarantee.
//!
//! ```text
//! config:   u8 layout | u8 flags | i64 max_ttl | i64 fixed_ttl | i64 min_ttl
//!           | i64 stale_seconds | i64 negative_seconds | text mode
//! hit:      u8 layout | u8 stale | u8 flags | u32 wire_len | wire
//!           | u16 chain_target_count | (u8 kind | text domain)×
//!           | u16 ip_count | text× | text resolved_ips
//! stats:    u8 layout | u8 flags | u64 hits | u64 misses | u64 stale | u64 negative
//!           | u64 evictions | u32 entry_count | u32 max_entries
//! snapshot: u8 layout | u32 count
//!           count × (bytes key | bytes query_name | u16 qtype | u16 qclass
//!                    | i64 created_ms | i64 expires_ms | i64 last_hit_ms
//!                    | u64 hit_count | u32 original_ttl | u32 response_size)
//! ```
//!
//! `config.flags` carries the four booleans the Go caller passes in (enabled, min TTL, stale
//! fallback, negative TTL). `hit.flags` only carries `is_negative`. `kind` is `0` CNAME and `1`
//! SVCB, exactly like the wire layer reports chain targets.

use crate::cache::{Hit, SnapshotEntry, Stats};
use crate::policy::{Config, TtlMode};

/// Layout version of every payload below; `dnsCachePayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 2;

const CONFIG_ENABLED: u8 = 1 << 0;
const CONFIG_MIN_TTL: u8 = 1 << 1;
const CONFIG_STALE_FALLBACK: u8 = 1 << 2;
const CONFIG_NEGATIVE_TTL: u8 = 1 << 3;

const HIT_NEGATIVE: u8 = 1 << 0;
const STATS_ENABLED: u8 = 1 << 0;

/// Decodes the configuration `dns_cache_native.go` encodes.
pub fn decode_config(data: &[u8]) -> Result<Config, String> {
    let mut reader = Reader::new(data, "config");
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(format!(
            "dns cache config layout {layout}, expected {LAYOUT_VERSION}"
        ));
    }
    let flags = reader.u8("flags")?;
    let config = Config {
        enabled: flags & CONFIG_ENABLED != 0,
        mode: TtlMode::Default,
        max_ttl_seconds: reader.i64("max_ttl")?,
        fixed_ttl_seconds: reader.i64("fixed_ttl")?,
        min_ttl_enabled: flags & CONFIG_MIN_TTL != 0,
        min_ttl_seconds: reader.i64("min_ttl")?,
        stale_fallback_enabled: flags & CONFIG_STALE_FALLBACK != 0,
        stale_fallback_seconds: reader.i64("stale_seconds")?,
        negative_ttl_enabled: flags & CONFIG_NEGATIVE_TTL != 0,
        negative_ttl_seconds: reader.i64("negative_seconds")?,
    };
    let mode = reader.text("mode")?;
    reader.expect_end()?;
    Ok(Config {
        mode: TtlMode::parse(mode.as_bytes()),
        ..config
    })
}

/// Encodes one lookup result.
pub fn encode_hit(hit: &Hit) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION, u8::from(hit.stale)];
    let mut flags = 0u8;
    if hit.is_negative {
        flags |= HIT_NEGATIVE;
    }
    out.push(flags);
    push_bytes(&mut out, &hit.wire);
    out.extend_from_slice(&(hit.chain_targets.len() as u16).to_le_bytes());
    for target in &hit.chain_targets {
        out.push(target.kind.code());
        push_text(&mut out, &target.domain);
    }
    out.extend_from_slice(&(hit.ip_list.len() as u16).to_le_bytes());
    for ip in &hit.ip_list {
        push_text(&mut out, ip);
    }
    push_text(&mut out, &hit.resolved_ips);
    out
}

/// Encodes the counters the Go layer reports.
pub fn encode_stats(stats: &Stats) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + 1 + 5 * 8 + 8);
    out.push(LAYOUT_VERSION);
    out.push(if stats.enabled { STATS_ENABLED } else { 0 });
    for value in [
        stats.total_hits,
        stats.total_misses,
        stats.stale_hits,
        stats.negative_hits,
        stats.evictions,
    ] {
        out.extend_from_slice(&value.to_le_bytes());
    }
    out.extend_from_slice(&stats.entry_count.to_le_bytes());
    out.extend_from_slice(&stats.max_entries.to_le_bytes());
    out
}

/// Encodes the projection the Android layer mirrors into the `dns_cache` table.
pub fn encode_snapshot(entries: &[SnapshotEntry]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(entries.len() as u32).to_le_bytes());
    for entry in entries {
        push_bytes(&mut out, &entry.key);
        push_bytes(&mut out, &entry.query_name);
        out.extend_from_slice(&entry.query_type.to_le_bytes());
        out.extend_from_slice(&entry.query_class.to_le_bytes());
        out.extend_from_slice(&entry.created_at_ms.to_le_bytes());
        out.extend_from_slice(&entry.expires_at_ms.to_le_bytes());
        out.extend_from_slice(&entry.last_hit_at_ms.to_le_bytes());
        out.extend_from_slice(&entry.hit_count.to_le_bytes());
        out.extend_from_slice(&entry.original_ttl.to_le_bytes());
        out.extend_from_slice(&entry.response_size.to_le_bytes());
    }
    out
}

fn push_bytes(out: &mut Vec<u8>, value: &[u8]) {
    out.extend_from_slice(&(value.len() as u32).to_le_bytes());
    out.extend_from_slice(value);
}

fn push_text(out: &mut Vec<u8>, value: &str) {
    push_bytes(out, value.as_bytes());
}

struct Reader<'a> {
    data: &'a [u8],
    position: usize,
    kind: &'static str,
}

impl<'a> Reader<'a> {
    fn new(data: &'a [u8], kind: &'static str) -> Self {
        Self {
            data,
            position: 0,
            kind,
        }
    }

    fn remaining(&self) -> usize {
        self.data.len() - self.position
    }

    fn take(&mut self, length: usize, field: &str) -> Result<&'a [u8], String> {
        if self.remaining() < length {
            return Err(format!(
                "dns cache {} payload is truncated ({field})",
                self.kind
            ));
        }
        let slice = &self.data[self.position..self.position + length];
        self.position += length;
        Ok(slice)
    }

    fn u8(&mut self, field: &str) -> Result<u8, String> {
        Ok(self.take(1, field)?[0])
    }

    #[cfg(test)]
    fn u16(&mut self, field: &str) -> Result<u16, String> {
        let bytes = self.take(2, field)?;
        Ok(u16::from_le_bytes([bytes[0], bytes[1]]))
    }

    fn u32(&mut self, field: &str) -> Result<u32, String> {
        let bytes = self.take(4, field)?;
        Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn i64(&mut self, field: &str) -> Result<i64, String> {
        let bytes = self.take(8, field)?;
        let mut value = [0u8; 8];
        value.copy_from_slice(bytes);
        Ok(i64::from_le_bytes(value))
    }

    fn text(&mut self, field: &str) -> Result<String, String> {
        let length = self.u32(field)? as usize;
        let bytes = self.take(length, field)?;
        String::from_utf8(bytes.to_vec())
            .map_err(|_| format!("dns cache {} payload field {field} is not UTF-8", self.kind))
    }

    fn expect_end(&self) -> Result<(), String> {
        if self.remaining() == 0 {
            Ok(())
        } else {
            Err(format!(
                "dns cache {} payload has {} trailing bytes",
                self.kind,
                self.remaining()
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::{ChainKind, ChainTarget};

    fn sample_hit() -> Hit {
        Hit {
            stale: true,
            wire: vec![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            is_negative: true,
            chain_targets: vec![ChainTarget {
                domain: "chain.example".to_string(),
                kind: ChainKind::Cname,
            }],
            ip_list: vec!["192.0.2.7".to_string()],
            resolved_ips: "192.0.2.7".to_string(),
        }
    }

    fn decode_hit(data: &[u8]) -> (bool, bool, Vec<u8>, Vec<ChainTarget>, Vec<String>, String) {
        let mut reader = Reader::new(data, "hit");
        assert_eq!(reader.u8("layout").unwrap(), LAYOUT_VERSION);
        let stale = reader.u8("stale").unwrap() != 0;
        let negative = reader.u8("flags").unwrap() & HIT_NEGATIVE != 0;
        let wire_len = reader.u32("wire_len").unwrap() as usize;
        let wire = reader.take(wire_len, "wire").unwrap().to_vec();
        let count = reader.u16("chain_target_count").unwrap() as usize;
        let mut targets = Vec::new();
        for _ in 0..count {
            let kind = ChainKind::from_code(reader.u8("kind").unwrap()).unwrap();
            targets.push(ChainTarget {
                domain: reader.text("domain").unwrap(),
                kind,
            });
        }
        let count = reader.u16("ip_count").unwrap() as usize;
        let mut ips = Vec::new();
        for _ in 0..count {
            ips.push(reader.text("ip").unwrap());
        }
        let resolved = reader.text("resolved_ips").unwrap();
        reader.expect_end().unwrap();
        (stale, negative, wire, targets, ips, resolved)
    }

    #[test]
    fn hit_layout_round_trips() {
        let hit = sample_hit();
        let (stale, negative, wire, targets, ips, resolved) = decode_hit(&encode_hit(&hit));
        assert!(stale);
        assert!(negative);
        assert_eq!(wire, hit.wire);
        assert_eq!(targets, hit.chain_targets);
        assert_eq!(ips, hit.ip_list);
        assert_eq!(resolved, hit.resolved_ips);
    }

    #[test]
    fn config_layout_round_trips() {
        let mut data = vec![LAYOUT_VERSION];
        data.push(CONFIG_ENABLED | CONFIG_STALE_FALLBACK | CONFIG_NEGATIVE_TTL);
        for value in [3600i64, 120, 60, 300, 30] {
            data.extend_from_slice(&value.to_le_bytes());
        }
        push_text(&mut data, "fixed_ttl");
        let config = decode_config(&data).unwrap();
        assert!(config.enabled);
        assert!(config.stale_fallback_enabled);
        assert!(config.negative_ttl_enabled);
        assert!(!config.min_ttl_enabled);
        assert_eq!(config.fixed_ttl_seconds, 120);
        assert_eq!(config.mode, TtlMode::FixedTtl);
        assert!(decode_config(&data[..data.len() - 1]).is_err());
        let mut trailing = data.clone();
        trailing.push(0);
        assert!(decode_config(&trailing).is_err());
        let mut wrong_layout = data;
        wrong_layout[0] = LAYOUT_VERSION + 1;
        assert!(decode_config(&wrong_layout).is_err());
    }

    #[test]
    fn stats_and_snapshot_layouts_are_walkable() {
        let stats = Stats {
            enabled: true,
            total_hits: 3,
            total_misses: 2,
            stale_hits: 1,
            negative_hits: 4,
            evictions: 5,
            entry_count: 6,
            max_entries: 4096,
        };
        let data = encode_stats(&stats);
        let mut reader = Reader::new(&data, "stats");
        assert_eq!(reader.u8("layout").unwrap(), LAYOUT_VERSION);
        assert_eq!(reader.u8("flags").unwrap() & STATS_ENABLED, STATS_ENABLED);
        for field in ["hits", "misses", "stale", "negative", "evictions"] {
            reader.i64(field).unwrap();
        }
        assert_eq!(reader.u32("entry_count").unwrap(), 6);
        assert_eq!(reader.u32("max_entries").unwrap(), 4096);
        reader.expect_end().unwrap();

        let entries = vec![SnapshotEntry {
            key: b"example.com:1:1".to_vec(),
            query_name: b"example.com".to_vec(),
            query_type: 1,
            query_class: 1,
            created_at_ms: 10,
            expires_at_ms: 20,
            last_hit_at_ms: 15,
            hit_count: 7,
            original_ttl: 300,
            response_size: 45,
        }];
        let data = encode_snapshot(&entries);
        let mut reader = Reader::new(&data, "snapshot");
        assert_eq!(reader.u8("layout").unwrap(), LAYOUT_VERSION);
        assert_eq!(reader.u32("count").unwrap(), 1);
        let key_len = reader.u32("key_len").unwrap() as usize;
        assert_eq!(reader.take(key_len, "key").unwrap(), b"example.com:1:1");
        let name_len = reader.u32("name_len").unwrap() as usize;
        assert_eq!(reader.take(name_len, "query_name").unwrap(), b"example.com");
        assert_eq!(reader.u16("qtype").unwrap(), 1);
        assert_eq!(reader.u16("qclass").unwrap(), 1);
        assert_eq!(reader.i64("created").unwrap(), 10);
        assert_eq!(reader.i64("expires").unwrap(), 20);
        assert_eq!(reader.i64("last_hit").unwrap(), 15);
        assert_eq!(reader.i64("hit_count").unwrap(), 7);
        assert_eq!(reader.u32("original_ttl").unwrap(), 300);
        assert_eq!(reader.u32("response_size").unwrap(), 45);
        reader.expect_end().unwrap();
    }
}
