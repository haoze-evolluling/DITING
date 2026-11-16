//! The DNS cache the standalone server answers from, plus the two JSON projections the UI reads.
//!
//! The container, the TTL policy, the negative cache, the stale window, the sweeper and the
//! projection are [`diting_dns_cache_core::Cache`]. What lives here is only what the Go engine kept:
//! the policy hand-off from `ApplyDNSConfig`, the `getDNSCacheStats` document (its field names are
//! read directly by `EngineStats.kt`, so they cannot change), the packed snapshot the cache mirror
//! consumes (`entries_packed`), and the single-flight shape (`begin_stale_refresh` /
//! `refresh_done`).
//!
//! Single flight itself stays in [`crate::dns`]: coalescing needs an async wait, which the cache
//! kernel deliberately does not have.

use std::sync::Arc;

use diting_dns_cache_core::policy::Config;
use diting_dns_cache_core::{Cache, Hit, SnapshotEntry, Stats};

/// One engine's cache handle.
pub struct DnsCache {
    cache: Arc<Cache>,
}

impl DnsCache {
    /// A disabled cache. `ApplyDNSConfig` publishes the real policy, so the engine can be built
    /// before any config arrives and still answer.
    pub fn new() -> Self {
        Self {
            cache: Cache::new(Config::default()),
        }
    }

    pub fn apply_policy(&self, config: Config) {
        self.cache.update_policy(config);
    }

    pub fn policy(&self) -> Config {
        self.cache.config()
    }

    pub fn clear(&self) {
        self.cache.clear();
    }

    pub fn is_enabled(&self) -> bool {
        self.cache.config().enabled
    }

    pub fn stale_fallback_enabled(&self) -> bool {
        self.cache.config().stale_fallback_enabled
    }

    /// A lookup that counts: the served path (`dnsCache.getFast`).
    pub fn get(&self, query: &[u8]) -> Option<Hit> {
        self.cache.get(query, true)
    }

    pub fn put(&self, query: &[u8], response: &[u8]) -> bool {
        self.cache.put(query, response)
    }

    /// Claims the one background refresh a stale hit is allowed to start.
    pub fn begin_stale_refresh(&self, query: &[u8]) -> bool {
        self.cache.refresh_begin(query)
    }

    pub fn end_stale_refresh(&self, query: &[u8]) {
        self.cache.refresh_done(query)
    }

    pub fn stats(&self) -> Stats {
        self.cache.stats()
    }

    pub fn snapshot(&self, limit: u32) -> Vec<SnapshotEntry> {
        self.cache.snapshot(limit)
    }
}

impl Default for DnsCache {
    fn default() -> Self {
        Self::new()
    }
}

/// `getDNSCacheStats`: the document `EngineStats.kt` reads with `optLong`/`optInt`/`optDouble`.
pub fn stats_json(stats: Stats) -> String {
    let total = stats.total_hits + stats.total_misses;
    let hit_ratio = if total > 0 {
        stats.total_hits as f64 / total as f64
    } else {
        0.0
    };
    let document = serde_json::json!({
        "enabled": stats.enabled,
        "totalHits": stats.total_hits,
        "totalMisses": stats.total_misses,
        "staleHits": stats.stale_hits,
        "negativeHits": stats.negative_hits,
        "hitRatio": hit_ratio,
        "entryCount": stats.entry_count,
        "maxEntries": stats.max_entries,
        "evictionCount": stats.evictions,
    });
    document.to_string()
}

/// `getDNSCacheSnapshot`: the hot entries in the packed layout `LogNative.mirrorRows` decodes.
///
/// This is the mirror's path. It used to be `entries_json` → `JSONArray` on the JVM → one
/// `LogMirrorEntry` per row → a re-packed request to the log kernel: four conversions and a JSON
/// document per snapshot. The bytes below are the log kernel's own mirror input, so Kotlin forwards
/// them untouched and the kernel projects them into `dns_cache` rows.
pub fn entries_packed(entries: &[SnapshotEntry]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + entries.len() * 64);
    out.extend_from_slice(&(entries.len() as u32).to_be_bytes());
    for entry in entries {
        push_bytes(&mut out, &entry.key);
        push_bytes(&mut out, &entry.query_name);
        out.extend_from_slice(&i32::from(entry.query_type).to_be_bytes());
        out.extend_from_slice(&i32::from(entry.query_class).to_be_bytes());
        out.extend_from_slice(&entry.created_at_ms.to_be_bytes());
        out.extend_from_slice(&entry.expires_at_ms.to_be_bytes());
        out.extend_from_slice(&entry.last_hit_at_ms.to_be_bytes());
        out.extend_from_slice(&(entry.hit_count as i64).to_be_bytes());
        out.extend_from_slice(&i64::from(entry.original_ttl).to_be_bytes());
        out.extend_from_slice(&(entry.response_size as i32).to_be_bytes());
    }
    out
}

/// `u32 length | bytes`, the string framing the log payloads use.
fn push_bytes(out: &mut Vec<u8>, value: &[u8]) {
    out.extend_from_slice(&(value.len() as u32).to_be_bytes());
    out.extend_from_slice(value);
}

/// `getDNSCacheEntries`: the array `DnsCacheMirror.kt` writes into the `dns_cache` table.
///
/// The names are the ones the old Go projection used, so the mirror keeps working unchanged;
/// names that are not valid UTF-8 (they came out of the wire that way) are replaced, which is what
/// `json.Marshal` did to an invalid `string`.
pub fn entries_json(entries: &[SnapshotEntry]) -> String {
    let document: Vec<serde_json::Value> = entries
        .iter()
        .map(|entry| {
            serde_json::json!({
                "key": String::from_utf8_lossy(&entry.key),
                "queryName": String::from_utf8_lossy(&entry.query_name),
                "queryType": entry.query_type,
                "queryClass": entry.query_class,
                "createdAt": entry.created_at_ms,
                "expiresAt": entry.expires_at_ms,
                "lastHitAt": entry.last_hit_at_ms,
                "hitCount": entry.hit_count,
                "originalTtlSeconds": entry.original_ttl,
                "responseSize": entry.response_size,
            })
        })
        .collect();
    serde_json::Value::Array(document).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_cache_core::policy::TtlMode;

    /// A one-question query wire, enough for the cache key builder.
    fn query(name: &str, qtype: u16) -> Vec<u8> {
        let mut out = vec![0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0];
        for label in name.trim_end_matches('.').split('.') {
            out.push(label.len() as u8);
            out.extend_from_slice(label.as_bytes());
        }
        out.push(0);
        out.extend_from_slice(&qtype.to_be_bytes());
        out.extend_from_slice(&1u16.to_be_bytes());
        out
    }

    fn response(name: &str, address: [u8; 4], ttl: u32) -> Vec<u8> {
        let mut out = query(name, 1);
        out[2] = 0x81;
        out[3] = 0x80;
        out[7] = 1;
        out.extend_from_slice(&[0xc0, 0x0c]);
        out.extend_from_slice(&1u16.to_be_bytes());
        out.extend_from_slice(&1u16.to_be_bytes());
        out.extend_from_slice(&ttl.to_be_bytes());
        out.extend_from_slice(&4u16.to_be_bytes());
        out.extend_from_slice(&address);
        out
    }

    #[test]
    fn caches_and_reports_the_go_documents() {
        let cache = DnsCache::new();
        cache.apply_policy(Config {
            enabled: true,
            mode: TtlMode::FollowDnsTtl,
            ..Config::default()
        });
        let query_wire = query("example.test.", 1);
        assert!(cache.get(&query_wire).is_none(), "cold");
        assert!(cache.put(&query_wire, &response("example.test.", [1, 2, 3, 4], 60)));

        let hit = cache.get(&query_wire).expect("warm");
        assert_eq!(hit.resolved_ips, "1.2.3.4");

        let stats = serde_json::from_str::<serde_json::Value>(&stats_json(cache.stats()))
            .expect("stats json");
        assert_eq!(stats["enabled"], serde_json::json!(true));
        assert_eq!(stats["entryCount"], serde_json::json!(1));
        assert_eq!(stats["totalHits"], serde_json::json!(1));
        assert_eq!(stats["totalMisses"], serde_json::json!(1));
        assert_eq!(stats["hitRatio"], serde_json::json!(0.5));
        assert_eq!(stats["evictionCount"], serde_json::json!(0));

        let entries = serde_json::from_str::<serde_json::Value>(&entries_json(&cache.snapshot(10)))
            .expect("entries json");
        let first = &entries[0];
        assert_eq!(
            first["key"],
            serde_json::json!("example.test:1:1"),
            "the key is the lowercased name without its trailing dot"
        );
        assert_eq!(first["queryName"], serde_json::json!("example.test"));
        assert_eq!(first["originalTtlSeconds"], serde_json::json!(60));
        assert_eq!(
            first["responseSize"],
            serde_json::json!(46),
            "the stored wire is the upstream answer, verbatim"
        );
    }

    #[test]
    fn the_packed_snapshot_is_the_mirror_input_layout() {
        let entries = vec![SnapshotEntry {
            key: b"example.test:1:1".to_vec(),
            query_name: b"example.test".to_vec(),
            query_type: 1,
            query_class: 1,
            created_at_ms: 1_000,
            expires_at_ms: 301_000,
            last_hit_at_ms: 2_000,
            hit_count: 7,
            original_ttl: 300,
            response_size: 46,
        }];
        let payload = entries_packed(&entries);
        let count = u32::from_be_bytes(payload[0..4].try_into().unwrap()) as usize;
        assert_eq!(count, 1);
        let mut offset = 4;
        let text = |offset: &mut usize| {
            let length =
                u32::from_be_bytes(payload[*offset..*offset + 4].try_into().unwrap()) as usize;
            *offset += 4;
            let value = String::from_utf8(payload[*offset..*offset + length].to_vec()).unwrap();
            *offset += length;
            value
        };
        assert_eq!(text(&mut offset), "example.test:1:1");
        assert_eq!(text(&mut offset), "example.test");
        let query_type = i32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap());
        assert_eq!(query_type, 1);
        offset += 4;
        let query_class = i32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap());
        assert_eq!(query_class, 1);
        offset += 4;
        // The five timestamps/counters plus `responseSize` stay in the order the kernel decodes.
        offset += 8 * 5;
        let response_size = i32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap());
        assert_eq!(response_size, 46);
        offset += 4;
        assert_eq!(
            offset,
            payload.len(),
            "the packed entry has no trailing bytes"
        );
    }

    #[test]
    fn empty_documents_match_the_old_shapes() {
        let stats = serde_json::from_str::<serde_json::Value>(&stats_json(Stats {
            enabled: false,
            total_hits: 0,
            total_misses: 0,
            stale_hits: 0,
            negative_hits: 0,
            evictions: 0,
            entry_count: 0,
            max_entries: 0,
        }))
        .expect("stats json");
        assert_eq!(stats["hitRatio"], serde_json::json!(0.0));
        assert_eq!(entries_json(&[]), "[]");
    }
}
