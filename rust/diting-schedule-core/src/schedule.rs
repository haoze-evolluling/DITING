//! The pure evaluator: one plan ([`evaluate`]) or many independent rules ([`evaluate_rules`]).
//!
//! A *plan* is the subscription shape — one `schedule` cadence applied to a list of `records`
//! (each with `lastAttemptAt`) — and produces `{due, nextDueAt, windowActive}`. Interval and the
//! two wall-clock cadences keep their original semantics byte-for-byte (the 3-day look-back, the
//! anchor day, every-other-day parity and "due from `lastAttemptAt`"), so
//! `diting-subscription-core` can delegate here without a behaviour change. `cron`, `window` and
//! `pause` extend the same interface.
//!
//! `now` and every wall-clock slot are injected as civil milliseconds ([`crate::civil`]); the
//! kernel never reads a clock or a timezone.

use std::collections::HashMap;

use serde_json::{json, Value};

use crate::civil::{self, DAY_MS};
use crate::cron::Cron;
use crate::payload;

const HOUR_MS: i64 = 3_600_000;

/// The cadence a plan follows. `Interval` is "every N hours since the last attempt"; the two
/// wall-clock cadences consume the caller-supplied `day → slot` table.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cadence {
    Interval,
    Daily,
    EveryOtherDay,
    Cron,
    Window,
    Pause,
}

impl Cadence {
    /// `schedule` (plan) or `kind` (rule) spelling → cadence; anything unknown is `Interval`, the
    /// legacy default the subscription kernel used.
    pub fn from(value: Option<&str>) -> Cadence {
        match value {
            Some("daily") => Cadence::Daily,
            Some("every_other_day") => Cadence::EveryOtherDay,
            Some("cron") => Cadence::Cron,
            Some("window") => Cadence::Window,
            Some("pause") => Cadence::Pause,
            _ => Cadence::Interval,
        }
    }
}

/// The `(id, lastAttemptAt)` rows a plan is evaluated against.
fn records(request: &Value) -> Vec<(i64, i64)> {
    payload::list(request, "records")
        .iter()
        .map(|record| {
            (
                payload::integer_or(record, "id", 0),
                payload::integer_or(record, "lastAttemptAt", 0),
            )
        })
        .collect()
}

/// The subscription-compatible slot plan. Mirrors the legacy `Plan` one-for-one.
struct SlotPlan {
    cadence: Cadence,
    interval_hours: i64,
    since_ms: i64,
    now_ms: i64,
    now_day: i64,
    since_before_day: i64,
    slots: HashMap<i64, i64>,
    anchor_day: i64,
}

impl SlotPlan {
    fn slot(&self, day: i64) -> Option<i64> {
        self.slots.get(&day).copied()
    }

    fn is_slot_day(&self, day: i64) -> bool {
        match self.cadence {
            Cadence::Daily => true,
            Cadence::EveryOtherDay => (day - self.anchor_day).rem_euclid(2) == 0,
            _ => false,
        }
    }

    /// The most recent scheduled moment at or before `now`; three days covers the every-other-day
    /// gap and a slot later today.
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

    /// Due from `lastAttemptAt`; a never-attempted row is due at once.
    fn is_due(&self, last_attempt_at: i64) -> bool {
        if last_attempt_at <= 0 {
            return true;
        }
        if self.cadence == Cadence::Interval {
            return self.now_ms - last_attempt_at >= self.interval_hours * HOUR_MS;
        }
        match self.latest_slot_at(self.now_ms) {
            Some(slot) => slot >= self.since_ms && last_attempt_at < slot,
            None => false,
        }
    }
}

fn build_slot_plan(request: &Value, cadence: Cadence) -> Option<SlotPlan> {
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
    Some(SlotPlan {
        cadence,
        interval_hours: payload::integer_or(request, "intervalHours", 24),
        since_ms,
        now_ms,
        now_day,
        since_before_day,
        slots,
        anchor_day,
    })
}

fn eval_slots(request: &Value, cadence: Cadence, now_ms: i64) -> Option<Value> {
    let plan = build_slot_plan(request, cadence)?;
    let entries = records(request);
    let due: Vec<i64> = entries
        .iter()
        .filter(|entry| plan.is_due(entry.1))
        .map(|entry| entry.0)
        .collect();
    let next_due = if entries.is_empty() {
        Value::Null
    } else if !due.is_empty() {
        json!(now_ms)
    } else {
        let next = if cadence == Cadence::Interval {
            let interval_ms = plan.interval_hours * HOUR_MS;
            let mut earliest = now_ms + interval_ms;
            for entry in &entries {
                let due_at = entry.1 + interval_ms;
                if due_at < earliest {
                    earliest = due_at;
                }
            }
            earliest
        } else {
            plan.next_slot_after(now_ms)?
        };
        json!(next)
    };
    Some(json!({ "due": due, "nextDueAt": next_due, "windowActive": false }))
}

fn eval_cron(request: &Value, now_ms: i64) -> Option<Value> {
    let cron = Cron::parse(payload::text(request, "cron")?.as_str()).ok()?;
    let entries = records(request);
    let latest = cron.latest_at_or_before(now_ms);
    let due: Vec<i64> = entries
        .iter()
        .filter(|entry| {
            let last = entry.1;
            if last <= 0 {
                true
            } else {
                latest.is_some_and(|occurrence| occurrence > last)
            }
        })
        .map(|entry| entry.0)
        .collect();
    let next_due = if entries.is_empty() {
        Value::Null
    } else if !due.is_empty() {
        json!(now_ms)
    } else {
        json!(cron.next_after(now_ms)?)
    };
    Some(json!({ "due": due, "nextDueAt": next_due, "windowActive": false }))
}

/// Whether `minute_of_day` falls inside `[start, end)`; `end < start` is an overnight window.
fn in_window(minute_of_day: i64, start: i64, end: i64) -> bool {
    if start < end {
        minute_of_day >= start && minute_of_day < end
    } else if start > end {
        minute_of_day >= start || minute_of_day < end
    } else {
        false
    }
}

fn eval_window(request: &Value, now_ms: i64) -> Option<Value> {
    let start = payload::integer(request, "windowStartMinutes")?;
    let end = payload::integer(request, "windowEndMinutes")?;
    let civil_now = civil::split(now_ms);
    let active = in_window(civil_now.minute_of_day, start, end);
    // The opening time of the window that contains (or most recently preceded) `now`.
    let start_today = civil::epoch_ms(civil_now.days, start);
    let overnight_and_before_end = start > end && civil_now.minute_of_day < end;
    let window_start = if overnight_and_before_end {
        start_today - DAY_MS
    } else if start <= civil_now.minute_of_day {
        start_today
    } else {
        start_today - DAY_MS
    };
    let entries = records(request);
    let due: Vec<i64> = entries
        .iter()
        .filter(|entry| {
            let last = entry.1;
            if last <= 0 {
                active
            } else {
                active && last < window_start
            }
        })
        .map(|entry| entry.0)
        .collect();
    let next_due = if entries.is_empty() {
        Value::Null
    } else if !due.is_empty() {
        json!(now_ms)
    } else {
        // The next opening strictly after now.
        let next_open = if start_today > now_ms {
            start_today
        } else {
            start_today + DAY_MS
        };
        json!(next_open)
    };
    Some(json!({ "due": due, "nextDueAt": next_due, "windowActive": active }))
}

fn eval_pause(request: &Value, now_ms: i64) -> Option<Value> {
    let until = payload::integer(request, "pauseUntilMs")?;
    let paused = now_ms < until;
    let entries = records(request);
    let due: Vec<i64> = entries
        .iter()
        .filter(|entry| {
            let last = entry.1;
            if paused {
                false
            } else {
                // Became due at `until`; not attempted since.
                last < until || last <= 0
            }
        })
        .map(|entry| entry.0)
        .collect();
    let next_due = if entries.is_empty() {
        Value::Null
    } else if !due.is_empty() {
        json!(now_ms)
    } else if paused {
        json!(until)
    } else {
        Value::Null
    };
    Some(json!({ "due": due, "nextDueAt": next_due, "windowActive": false }))
}

/// One evaluation for a whole plan: the due ids, the next due moment and whether a window is open.
pub fn evaluate(request: &Value) -> Option<Value> {
    let cadence = Cadence::from(request.get("schedule").and_then(Value::as_str));
    let now_ms = payload::integer_or(request, "nowMs", 0);
    match cadence {
        Cadence::Cron => eval_cron(request, now_ms),
        Cadence::Window => eval_window(request, now_ms),
        Cadence::Pause => eval_pause(request, now_ms),
        _ => eval_slots(request, cadence, now_ms),
    }
}

/// Evaluates a `{ "rules": [{ "id", "kind", ... }] }` document, aggregating every rule's due ids,
/// the earliest next moment and whether any window is currently open. Each rule is evaluated by
/// the same [`evaluate`] path, so the two entry points cannot disagree.
pub fn evaluate_rules(now_ms: i64, document: &Value) -> Value {
    let now_day = civil::split(now_ms).days;
    let mut due: Vec<Value> = Vec::new();
    let mut next: Option<i64> = None;
    let mut window_active = false;
    for rule in payload::list(document, "rules") {
        let id = rule.get("id").cloned().unwrap_or(Value::Null);
        let mut request = rule.clone();
        request["schedule"] = rule
            .get("kind")
            .cloned()
            .unwrap_or_else(|| json!("interval"));
        request["nowMs"] = json!(now_ms);
        request["nowDay"] = json!(now_day);
        request["records"] = json!([
            { "id": id, "lastAttemptAt": rule.get("lastAttemptAt").cloned().unwrap_or_else(|| json!(0)) }
        ]);
        let Some(answer) = evaluate(&request) else {
            continue;
        };
        if answer["due"]
            .as_array()
            .is_some_and(|rows| !rows.is_empty())
        {
            due.push(id);
        }
        if let Some(moment) = answer["nextDueAt"].as_i64() {
            next = Some(next.map_or(moment, |current| current.min(moment)));
        }
        if answer["windowActive"].as_bool().unwrap_or(false) {
            window_active = true;
        }
    }
    json!({ "due": due, "nextDueAt": next, "windowActive": window_active })
}
