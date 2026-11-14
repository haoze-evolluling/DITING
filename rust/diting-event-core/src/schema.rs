//! The frozen event envelope (`diting.event/1`).
//!
//! ```
//! { "schema": "diting.event/1", "event": "state_changed", "ts": 1710000000000,
//!   "source": "android",
//!   "data": { "workMode": "normal", "running": true, "reclaiming": false, "persisted": true,
//!             "startedAt": 1710000000000, "pausedUntil": 0, "error": null } }
//! ```
//!
//! Bumping [`SCHEMA_VERSION`] is a breaking change for every external consumer, so it is frozen for
//! the whole 2.5.x line: fields may be added, never renamed or removed.

use serde_json::{json, Map, Value};

/// Versioned envelope identifier; the `<prefix>/<n>` suffix is what consumers switch on.
pub const SCHEMA_VERSION: &str = "diting.event/1";
/// The state-change event name.
pub const EVENT_STATE_CHANGED: &str = "state_changed";

fn normalize_work_mode(work_mode: &str) -> &str {
    match work_mode {
        "normal" | "dns" | "express" => work_mode,
        _ => "unknown",
    }
}

/// Builds the frozen `state_changed` envelope. `started_at`/`paused_until` of `0` mean "not
/// running" / "not paused"; negative inputs clamp to `0`.
// Eight values mirror the seven JNI fields plus the injected timestamp; a struct would just move
// the same fields around the boundary.
#[allow(clippy::too_many_arguments)]
pub fn state_changed(
    work_mode: &str,
    running: bool,
    reclaiming: bool,
    persisted: bool,
    started_at: i64,
    paused_until: i64,
    error: Option<&str>,
    ts_ms: i64,
) -> Value {
    json!({
        "schema": SCHEMA_VERSION,
        "event": EVENT_STATE_CHANGED,
        "ts": ts_ms.max(0),
        "source": "android",
        "data": {
            "workMode": normalize_work_mode(work_mode),
            "running": running,
            "reclaiming": reclaiming,
            "persisted": persisted,
            "startedAt": started_at.max(0),
            "pausedUntil": paused_until.max(0),
            "error": error.map(str::to_owned),
        }
    })
}

/// Validates an envelope against the frozen schema. Returns the first problem as a static string.
pub fn validate(value: &Value) -> Result<(), &'static str> {
    let object = value.as_object().ok_or("envelope is not an object")?;
    if object.get("schema").and_then(Value::as_str) != Some(SCHEMA_VERSION) {
        return Err("unexpected schema version");
    }
    let event = object
        .get("event")
        .and_then(Value::as_str)
        .ok_or("missing event name")?;
    if event != EVENT_STATE_CHANGED {
        return Err("unexpected event name");
    }
    let ts = object
        .get("ts")
        .and_then(Value::as_i64)
        .ok_or("missing ts")?;
    if ts < 0 {
        return Err("negative ts");
    }
    if object.get("source").and_then(Value::as_str).is_none() {
        return Err("missing source");
    }
    let data = object
        .get("data")
        .and_then(Value::as_object)
        .ok_or("missing data")?;
    validate_state_data(data)
}

fn validate_state_data(data: &Map<String, Value>) -> Result<(), &'static str> {
    let work_mode = data
        .get("workMode")
        .and_then(Value::as_str)
        .ok_or("missing data.workMode")?;
    if !matches!(work_mode, "normal" | "dns" | "express" | "unknown") {
        return Err("invalid data.workMode");
    }
    for flag in ["running", "reclaiming", "persisted"] {
        if data.get(flag).and_then(Value::as_bool).is_none() {
            return Err("missing boolean data flag");
        }
    }
    for number in ["startedAt", "pausedUntil"] {
        let value = data
            .get(number)
            .and_then(Value::as_i64)
            .ok_or("missing numeric data field")?;
        if value < 0 {
            return Err("negative numeric data field");
        }
    }
    match data.get("error") {
        Some(Value::Null) | Some(Value::String(_)) => Ok(()),
        _ => Err("invalid data.error"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_round_trips_through_validation() {
        let envelope = state_changed("normal", true, false, true, 1_710_000_000_000, 0, None, 42);
        assert_eq!(envelope["schema"], json!(SCHEMA_VERSION));
        assert_eq!(envelope["event"], json!(EVENT_STATE_CHANGED));
        assert_eq!(envelope["data"]["workMode"], json!("normal"));
        assert!(validate(&envelope).is_ok());
    }

    #[test]
    fn unknown_work_mode_folds_to_unknown() {
        let envelope = state_changed("weird", false, false, false, 0, 0, Some("boom"), 1);
        assert_eq!(envelope["data"]["workMode"], json!("unknown"));
        assert_eq!(envelope["data"]["error"], json!("boom"));
        assert!(validate(&envelope).is_ok());
    }

    #[test]
    fn rejects_broken_envelopes() {
        assert!(validate(&json!("nope")).is_err());
        assert!(validate(&json!({ "schema": "diting.event/2" })).is_err());
        let mut envelope = state_changed("dns", true, false, true, 1, 0, None, 5);
        envelope["data"]["running"] = json!("yes");
        assert!(validate(&envelope).is_err());
        let mut missing = state_changed("express", false, false, false, 0, 0, None, 5);
        missing["data"]
            .as_object_mut()
            .unwrap()
            .remove("pausedUntil");
        assert!(validate(&missing).is_err());
    }
}
