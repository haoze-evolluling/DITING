use crate::engine::Engine;

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

pub fn engine_stats_json(engine: &Engine) -> String {
    let mut document = serde_json::json!({
        "total": engine.total_queries(),
        "blocked": engine.blocked_queries(),
        "dropped_logs": engine.logs().dropped(),
    });
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
