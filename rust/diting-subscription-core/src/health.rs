//! Subscription health classification (R3): `ok` / `unchanged` / `cached` / `failed`.
//!
//! The desktop filter lists expose a health verdict per list, and the Android subscription page only
//! showed a raw "abnormal" count. This module derives the finer status from the fields the app
//! already persists on each `subscription` row — no schema change is required — plus, during a live
//! update, the verdict of the attempt itself (so a `304 Not Modified` can be told apart from a fresh
//! download). A failure that still has rules to serve is `cached`, matching the "keep the old rules"
//! behaviour; only a failure with nothing to serve is `failed`.
//!
//! The classification is a pure function; the FFI layer only marshals JSON.

use serde_json::{json, Value};

/// Fresh content was downloaded and stored.
pub const OK: &str = "ok";
/// The server answered `304 Not Modified`; the stored rules stay.
pub const UNCHANGED: &str = "unchanged";
/// The last attempt failed but older rules are still being served.
pub const CACHED: &str = "cached";
/// The last attempt failed and there are no rules to fall back on.
pub const FAILED: &str = "failed";

/// One subscription's settled health.
///
/// `last_result` is the verdict of the most recent attempt when known (`ok` / `unchanged` /
/// `failed`); it takes precedence because a `304` cannot be reconstructed from stored columns. When
/// it is `None` the persisted `import_state`, `rule_count` and `last_updated` decide.
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

/// `health.classify`: one row in, one `{status}` out.
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

/// `health.summary`: count each status across the rows the app already loaded, so the page can show
/// "正常 N / 缓存 N / 失败 N" without a second classification in Dart.
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
        // No rules and never updated: nothing to serve.
        assert_eq!(classify("ready", 0, 0, None), FAILED);
        // A failed import that still has rules keeps them: cached.
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
