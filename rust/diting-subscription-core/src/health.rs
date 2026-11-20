use serde_json::{json, Value};

pub const OK: &str = "ok";
pub const UNCHANGED: &str = "unchanged";
pub const CACHED: &str = "cached";
pub const FAILED: &str = "failed";

pub fn classify(
    import_state: &str,
    rule_count: i64,
    last_updated: i64,
    last_result: Option<&str>,
) -> &'static str {
    let has_rules = rule_count > 0;
    match last_result {
        Some("unchanged") => UNCHANGED,
        Some("ok") => OK,
        Some("failed") => {
            if has_rules {
                CACHED
            } else {
                FAILED
            }
        }
        _ => {
            if import_state == "failed" {
                if has_rules {
                    CACHED
                } else {
                    FAILED
                }
            } else if last_updated > 0 {
                OK
            } else if has_rules {
                CACHED
            } else {
                FAILED
            }
        }
    }
}

pub fn classify_request(request: &Value) -> Value {
    let state = request
        .get("importState")
        .and_then(Value::as_str)
        .unwrap_or("ready");
    let rule_count = request
        .get("ruleCount")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let last_updated = request
        .get("lastUpdated")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let last_result = request.get("lastResult").and_then(Value::as_str);
    json!({ "status": classify(state, rule_count, last_updated, last_result) })
}

pub fn summary_request(request: &Value) -> Value {
    let mut ok = 0u32;
    let mut unchanged = 0u32;
    let mut cached = 0u32;
    let mut failed = 0u32;
    if let Some(rows) = request.get("rows").and_then(Value::as_array) {
        for row in rows {
            let state = row
                .get("importState")
                .and_then(Value::as_str)
                .unwrap_or("ready");
            let rule_count = row.get("ruleCount").and_then(Value::as_i64).unwrap_or(0);
            let last_updated = row.get("lastUpdated").and_then(Value::as_i64).unwrap_or(0);
            match classify(state, rule_count, last_updated, None) {
                OK => ok += 1,
                UNCHANGED => unchanged += 1,
                CACHED => cached += 1,
                _ => failed += 1,
            }
        }
    }
    json!({
        "ok": ok,
        "unchanged": unchanged,
        "cached": cached,
        "failed": failed,
        "total": ok + unchanged + cached + failed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fresh_and_never_and_cached_and_failed() {
        assert_eq!(classify("ready", 10, 1_000, None), OK);
        assert_eq!(classify("ready", 0, 0, None), FAILED);
        assert_eq!(classify("failed", 10, 1_000, None), CACHED);
        assert_eq!(classify("failed", 0, 0, None), FAILED);
    }

    #[test]
    fn a_live_verdict_takes_precedence() {
        assert_eq!(classify("ready", 10, 1_000, Some("unchanged")), UNCHANGED);
        assert_eq!(classify("ready", 10, 1_000, Some("ok")), OK);
        assert_eq!(classify("ready", 10, 1_000, Some("failed")), CACHED);
        assert_eq!(classify("ready", 0, 0, Some("failed")), FAILED);
    }

    #[test]
    fn summary_counts_every_row() {
        let answer = summary_request(&json!({
            "rows": [
                {"importState": "ready", "ruleCount": 5, "lastUpdated": 100},
                {"importState": "failed", "ruleCount": 5, "lastUpdated": 100},
                {"importState": "failed", "ruleCount": 0, "lastUpdated": 0},
            ],
        }));
        assert_eq!(answer["ok"], json!(1));
        assert_eq!(answer["cached"], json!(1));
        assert_eq!(answer["failed"], json!(1));
        assert_eq!(answer["total"], json!(3));
    }
}
