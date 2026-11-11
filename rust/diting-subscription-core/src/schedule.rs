//! Subscription auto-update timing: interval mode and the two wall-clock schedules.
//!
//! The calendar conversion (local date + minutes to an epoch) stays in Dart, which hands over a
//! small `day → slot` table built with `DateTime`; the rules on top of it — the 3-day look-back,
//! the anchor day, every-other-day parity and "due from `lastAttemptAt`, not `lastUpdated`" —
//! live here. `now` is injected, so the tests pin every boundary.

use std::collections::HashMap;

use serde_json::{json, Value};

use crate::payload;

const HOUR_MS: i64 = 3_600_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Schedule {
    Interval,
    Daily,
    EveryOtherDay,
}

impl Schedule {
    fn from(value: Option<&str>) -> Self {
        match value {
            Some("daily") => Schedule::Daily,
            Some("every_other_day") => Schedule::EveryOtherDay,
            _ => Schedule::Interval,
        }
    }

    fn timed(self) -> bool {
        self != Schedule::Interval
    }
}

struct Plan {
    schedule: Schedule,
    interval_hours: i64,
    since_ms: i64,
    now_ms: i64,
    now_day: i64,
    since_before_day: i64,
    slots: HashMap<i64, i64>,
    anchor_day: i64,
}

impl Plan {
    fn slot(&self, day: i64) -> Option<i64> {
        self.slots.get(&day).copied()
    }

    fn is_slot_day(&self, day: i64) -> bool {
        match self.schedule {
            Schedule::Daily => true,
            Schedule::EveryOtherDay => (day - self.anchor_day).rem_euclid(2) == 0,
            Schedule::Interval => false,
        }
    }

    /// The most recent scheduled moment at or before `now`; three days covers the
    /// every-other-day gap and a slot later today.
    fn latest_slot_at(&self, now: i64) -> Option<i64> {
        for offset in 0..3 {
            let day = self.now_day - offset;
            if !self.is_slot_day(day) {
                continue;
            }
            if let Some(slot) = self.slot(day) {
                if slot <= now {
                    return Some(slot);
                }
            }
        }
        None
    }

    /// The first scheduled moment strictly after `from`; the anchor day makes this wait for the
    /// next slot when the chosen time already passed.
    fn next_slot_after(&self, from: i64) -> Option<i64> {
        let start = if self.now_ms < self.since_ms {
            self.since_before_day
        } else {
            self.now_day
        };
        for offset in 0..6 {
            let day = start + offset;
            if !self.is_slot_day(day) {
                continue;
            }
            let slot = self.slot(day)?;
            if slot > from {
                return Some(slot);
            }
        }
        None
    }

    /// Due from `lastAttemptAt`; a 304-only row must not look due forever.
    fn is_due(&self, last_attempt_at: i64) -> bool {
        if last_attempt_at <= 0 {
            return true;
        }
        if !self.schedule.timed() {
            return self.now_ms - last_attempt_at >= self.interval_hours * HOUR_MS;
        }
        match self.latest_slot_at(self.now_ms) {
            Some(slot) => slot >= self.since_ms && last_attempt_at < slot,
            None => false,
        }
    }
}

fn build_plan(request: &Value) -> Option<Plan> {
    let schedule = Schedule::from(request.get("schedule").and_then(Value::as_str));
    let since_ms = payload::integer_or(request, "sinceMs", 0);
    let now_ms = payload::integer_or(request, "nowMs", 0);
    let now_day = payload::integer(request, "nowDay")?;
    let since_day = payload::integer(request, "sinceDay").unwrap_or(0);
    let since_before_day = payload::integer(request, "sinceBeforeDay").unwrap_or(since_day);
    let mut slots = HashMap::new();
    for slot in payload::list(request, "slots") {
        let day = payload::integer(slot, "day")?;
        let ms = payload::integer(slot, "ms")?;
        slots.insert(day, ms);
    }
    let anchor_day = if since_ms <= 0 {
        0
    } else if slots.get(&since_day).copied().unwrap_or(i64::MIN) >= since_ms {
        since_day
    } else {
        since_day + 1
    };
    Some(Plan {
        schedule,
        interval_hours: payload::integer_or(request, "intervalHours", 24),
        since_ms,
        now_ms,
        now_day,
        since_before_day,
        slots,
        anchor_day,
    })
}

struct Entry {
    id: i64,
    last_attempt_at: i64,
}

fn entries(request: &Value) -> Vec<Entry> {
    payload::list(request, "records")
        .iter()
        .map(|record| Entry {
            id: payload::integer_or(record, "id", 0),
            last_attempt_at: payload::integer_or(record, "lastAttemptAt", 0),
        })
        .collect()
}

/// One evaluation for a whole list: the due ids and the next due moment.
pub fn evaluate(request: &Value) -> Option<Value> {
    let plan = build_plan(request)?;
    let entries = entries(request);
    let due: Vec<i64> = entries
        .iter()
        .filter(|entry| plan.is_due(entry.last_attempt_at))
        .map(|entry| entry.id)
        .collect();
    if entries.is_empty() {
        return Some(json!({ "due": [], "nextDueAt": null }));
    }
    if !due.is_empty() {
        return Some(json!({ "due": due, "nextDueAt": plan.now_ms }));
    }
    let next = if plan.schedule.timed() {
        plan.next_slot_after(plan.now_ms)?
    } else {
        let interval_ms = plan.interval_hours * HOUR_MS;
        let mut earliest = plan.now_ms + interval_ms;
        for entry in &entries {
            let due_at = entry.last_attempt_at + interval_ms;
            if due_at < earliest {
                earliest = due_at;
            }
        }
        earliest
    };
    Some(json!({ "due": due, "nextDueAt": next }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: i64 = HOUR_MS;
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
