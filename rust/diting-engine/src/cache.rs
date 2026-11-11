//! The DNS cache the standalone server answers from, plus the two JSON projections the UI reads.
//!
//! The container, the TTL policy, the negative cache, the stale window, the sweeper and the
//! projection are [`diting_dns_cache_core::Cache`]. What lives here is only what the Go engine kept:
//! the policy hand-off from `ApplyDNSConfig`, the `getDNSCacheStats` / `getDNSCacheEntries`
//! documents (field names are read directly by `EngineStats.kt` and `DnsCacheMirror.kt`, so they
//! cannot change) and the single-flight shape (`begin_stale_refresh` / `refresh_done`).
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
