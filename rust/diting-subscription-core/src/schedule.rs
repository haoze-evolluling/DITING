//! Subscription auto-update timing.
//!
//! The rules themselves moved to `diting-schedule-core` (`Cadence` + the pure evaluator); this
//! module is the thin subscription adapter that keeps the public `schedule.evaluate` payload — a
//! plan with `records`, returning `{due, nextDueAt}` — unchanged, so no behavioural regression can
//! hide behind the extraction. `now` and the local `day → slot` table stay injected by Dart.

use serde_json::{json, Value};

/// One evaluation for a whole list: the due ids and the next due moment.
///
/// Delegates to [`diting_schedule_core::evaluate`] and drops its `windowActive` field, which the
/// subscription UI does not consume.
pub fn evaluate(request: &Value) -> Option<Value> {
    let answer = diting_schedule_core::evaluate(request)?;
    Some(json!({
        "due": answer.get("due").cloned().unwrap_or_else(|| json!([])),
        "nextDueAt": answer.get("nextDueAt").cloned().unwrap_or(Value::Null),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: i64 = 3_600_000;
    const DAY: i64 = 86_400_000;

    /// Slots at 04:00 local for days in `[base-4, base+8]`; the epoch grid is synthetic (each day
    /// is exactly `DAY` long), which keeps the rules testable in any time zone.
    fn slots(around: i64) -> Value {
        let mut list = Vec::new();
        for day in (around - 4)..=(around + 8) {
            list.push(json!({ "day": day, "ms": day * DAY + 4 * HOUR }));
        }
        json!(list)
    }

    fn request(schedule: &str, since_ms: i64, now_ms: i64) -> Value {
        let now_day = now_ms.div_euclid(DAY);
        let since_day = since_ms.max(0).div_euclid(DAY);
        json!({
            "schedule": schedule,
            "intervalHours": 24,
            "timeMinutes": 4 * 60,
            "sinceMs": since_ms,
            "nowMs": now_ms,
            "nowDay": now_day,
            "sinceDay": since_day,
            "sinceBeforeDay": (since_ms - 1).max(0).div_euclid(DAY),
            "slots": slots(now_day.max(since_day)),
            "records": [],
        })
    }

    fn evaluate_records(base: Value, rows: &[(i64, i64)]) -> Value {
        let mut request = base;
        request["records"] = Value::Array(
            rows.iter()
                .map(|(id, last)| json!({ "id": id, "lastAttemptAt": last }))
                .collect(),
        );
        evaluate(&request).unwrap()
    }

    #[test]
    fn no_records_means_no_next_time() {
        let base = request("interval", 0, 100 * DAY);
        assert_eq!(
            evaluate_records(base, &[]),
            json!({ "due": [], "nextDueAt": null })
        );
    }
}
