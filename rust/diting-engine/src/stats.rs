//! The `getStats` document.
//!
//! `EngineStats.kt` reads three fields with `optLong` and never shows the raw JSON, but the names are
//! still the contract: `total`, `blocked`, `dropped_logs`. `dropped_logs` is the batch buffer's drop
//! counter, i.e. rows the UI will never see because the engine outran its writer.

use crate::engine::Engine;

/// `StatsSnapshot`: the six counters `EngineStats.snapshot` publishes, packed as big-endian
/// `u64`s (`total | blocked | dropped_logs | cache_hits | cache_misses | cache_entries`).
///
/// The dashboard polls this every few seconds for the whole life of the tunnel. It used to take two
/// JNI calls, two JSON encoders, two Java `String` conversions and two `JSONObject` parses per
/// poll; the fixed layout lets Kotlin read the numbers with one `ByteBuffer`.
pub fn engine_stats_snapshot(engine: &Engine) -> Vec<u8> {
    let cache = engine.cache().stats();
    let mut out = Vec::with_capacity(6 * 8);
    for value in [
        engine.total_queries(),
        engine.blocked_queries(),
        engine.logs().dropped(),
        cache.total_hits,
        cache.total_misses,
        u64::from(cache.entry_count),
    ] {
        out.extend_from_slice(&value.to_be_bytes());
    }
    out
}

/// `GetStats`: the JSON `EngineStats.snapshot` parses.
pub fn engine_stats_json(engine: &Engine) -> String {
    let mut document = serde_json::json!({
        "total": engine.total_queries(),
        "blocked": engine.blocked_queries(),
        "dropped_logs": engine.logs().dropped(),
    });
    // The TUN counters are additive: the three fields above are untouched, a UI that ignores
    // unknown keys keeps working, and a support log can finally say why a flow was dropped.
    if let Some(tun) = engine.tun_document() {
        document["tun"] = tun;
    }
    document.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fresh_engine_reports_zeroes() {
        let engine = Engine::new();
        let parsed: serde_json::Value =
            serde_json::from_str(&engine_stats_json(&engine)).expect("json");
        assert_eq!(parsed["total"], serde_json::json!(0));
        assert_eq!(parsed["blocked"], serde_json::json!(0));
        assert_eq!(parsed["dropped_logs"], serde_json::json!(0));

        engine.note_query(true);
        let parsed: serde_json::Value =
            serde_json::from_str(&engine_stats_json(&engine)).expect("json");
        assert_eq!(parsed["total"], serde_json::json!(1));
        assert_eq!(parsed["blocked"], serde_json::json!(1));
    }

    #[test]
    fn the_packed_snapshot_carries_the_six_counters_in_order() {
        let engine = Engine::new();
        engine.note_query(true);
        let snapshot = engine_stats_snapshot(&engine);
        assert_eq!(snapshot.len(), 6 * 8);
        let read = |index: usize| {
            u64::from_be_bytes(snapshot[index * 8..index * 8 + 8].try_into().unwrap())
        };
        assert_eq!(read(0), 1, "total");
        assert_eq!(read(1), 1, "blocked");
        assert_eq!(read(2), 0, "dropped");
        assert_eq!(read(3), 0, "cache hits");
        assert_eq!(read(4), 0, "cache misses");
        assert_eq!(read(5), 0, "cache entries");
    }
}
