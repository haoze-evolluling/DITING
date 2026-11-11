//! The `getStats` document.
//!
//! `EngineStats.kt` reads three fields with `optLong` and never shows the raw JSON, but the names are
//! still the contract: `total`, `blocked`, `dropped_logs`. `dropped_logs` is the batch buffer's drop
//! counter, i.e. rows the UI will never see because the engine outran its writer.

use crate::engine::Engine;

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
}
