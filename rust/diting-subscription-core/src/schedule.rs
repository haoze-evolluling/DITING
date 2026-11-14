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
    fn interval_boundaries() {
        let now = 100 * DAY + 9 * HOUR;
        let base = request("interval", 0, now);
        let answer = evaluate_records(base.clone(), &[(1, 0)]);
        assert_eq!(answer["due"], json!([1]));
        assert_eq!(answer["nextDueAt"], json!(now));

        let answer = evaluate_records(base.clone(), &[(1, now - 23 * HOUR)]);
        assert_eq!(answer["due"], json!([]));
        assert_eq!(answer["nextDueAt"], json!(now + HOUR));

        let answer = evaluate_records(base, &[(1, now - 24 * HOUR)]);
        assert_eq!(answer["due"], json!([1]));
    }

    #[test]
    fn interval_picks_the_earliest_of_several_rows() {
        let now = 100 * DAY + 9 * HOUR;
        let base = request("interval", 0, now);
        let answer = evaluate_records(
            base,
            &[
                (1, now - 2 * HOUR),
                (2, now - 20 * HOUR),
                (3, now - 10 * HOUR),
            ],
        );
        assert_eq!(answer["due"], json!([]));
        assert_eq!(answer["nextDueAt"], json!(now + 4 * HOUR));
    }

    #[test]
    fn daily_waits_for_the_slot_and_uses_last_attempt() {
        let since = 100 * DAY + 12 * HOUR;
        let now = 102 * DAY + 9 * HOUR;
        let base = request("daily", since, now);

        let answer = evaluate_records(base.clone(), &[(1, 101 * DAY + 5 * HOUR)]);
        assert_eq!(answer["due"], json!([1]));

        let fresh = 102 * DAY + 4 * HOUR + 60_000;
        let answer = evaluate_records(base, &[(1, fresh)]);
        assert_eq!(answer["due"], json!([]));
        assert_eq!(answer["nextDueAt"], json!(103 * DAY + 4 * HOUR));
    }

    #[test]
    fn a_slot_that_already_passed_today_does_not_fire_at_once() {
        let since = 102 * DAY + 12 * HOUR;
        let now = since + 60_000;
        let base = request("daily", since, now);
        let answer = evaluate_records(base, &[(1, 100 * DAY + 4 * HOUR)]);
        assert_eq!(answer["due"], json!([]));
        assert_eq!(answer["nextDueAt"], json!(103 * DAY + 4 * HOUR));
    }

    #[test]
    fn every_other_day_counts_from_the_first_slot() {
        let since = 102 * DAY + 12 * HOUR;
        let now = 104 * DAY + 9 * HOUR;
        let base = request("every_other_day", since, now);
        let ran = 103 * DAY + 4 * HOUR + 5 * 60_000;
        let answer = evaluate_records(base.clone(), &[(1, ran)]);
        assert_eq!(answer["due"], json!([]));
        assert_eq!(answer["nextDueAt"], json!(105 * DAY + 4 * HOUR));

        let answer = evaluate_records(
            request("every_other_day", since, 105 * DAY + 4 * HOUR + 60_000),
            &[(1, ran)],
        );
        assert_eq!(answer["due"], json!([1]));
    }

    #[test]
    fn never_attempted_is_due_at_once() {
        let base = request("daily", 102 * DAY + 12 * HOUR, 102 * DAY + 13 * HOUR);
        let answer = evaluate_records(base, &[(1, 0)]);
        assert_eq!(answer["due"], json!([1]));
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
