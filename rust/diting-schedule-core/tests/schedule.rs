//! Behavioural tests for `diting-schedule-core`, pinning every cadence boundary.
//!
//! The wall-clock tests feed a synthetic `day → slot` table (a fixed `DAY` grid) so the rules are
//! timezone-independent; the DST test feeds a 23-hour day to prove the kernel follows the injected
//! slots rather than assuming a fixed day length. Cron/window/pause use real civil dates.

use diting_schedule_core::{evaluate, evaluate_rules};
use serde_json::{json, Value};

const HOUR: i64 = 3_600_000;
const DAY: i64 = 86_400_000;

/// Slots at 04:00 for days in `[around-4, around+8]`, on the synthetic fixed grid.
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
    evaluate(&request).expect("evaluated")
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
        json!({ "due": [], "nextDueAt": null, "windowActive": false })
    );
}

#[test]
fn daily_across_a_short_dst_day_follows_the_injected_slot() {
    // Spring forward: this day is 23 hours long, so the 04:00 slot lands one hour "early" in
    // absolute terms. The kernel must follow the table, not assume 24-hour days.
    let day = 20_000i64;
    let dst_slot = day * DAY + 3 * HOUR;
    let next_slot = (day + 1) * DAY + 4 * HOUR;
    let base = json!({
        "schedule": "daily",
        "intervalHours": 24,
        "sinceMs": dst_slot - DAY,
        "nowMs": dst_slot + 60_000,
        "nowDay": day,
        "sinceDay": day - 1,
        "sinceBeforeDay": day - 2,
        "slots": [
            { "day": day - 1, "ms": (day - 1) * DAY + 4 * HOUR },
            { "day": day, "ms": dst_slot },
            { "day": day + 1, "ms": next_slot },
        ],
        "records": [],
    });
    let due = evaluate_records(base.clone(), &[(1, dst_slot - HOUR)]);
    assert_eq!(due["due"], json!([1]));

    let fresh = evaluate_records(base, &[(1, dst_slot + 60_000)]);
    assert_eq!(fresh["due"], json!([]));
    assert_eq!(fresh["nextDueAt"], json!(next_slot));
}

fn civil_ms(year: i64, month: i64, day: i64, hour: i64, minute: i64) -> i64 {
    let days = diting_schedule_core::civil::days_from_civil(year, month, day);
    diting_schedule_core::civil::epoch_ms(days, hour * 60 + minute)
}

#[test]
fn cron_crosses_midnight_and_month_boundary() {
    let now = civil_ms(2024, 1, 31, 23, 45);
    let base = json!({
        "schedule": "cron",
        "cron": "30 23 * * *",
        "nowMs": now,
        "records": [],
    });
    // Attempted the previous night: the 23:30 occurrence tonight makes it due.
    let due = evaluate_records(base.clone(), &[(1, civil_ms(2024, 1, 30, 23, 30))]);
    assert_eq!(due["due"], json!([1]));
    // Already ran tonight: next is tomorrow, 2024-02-01 23:30.
    let fresh = evaluate_records(base, &[(1, now)]);
    assert_eq!(fresh["due"], json!([]));
    assert_eq!(fresh["nextDueAt"], json!(civil_ms(2024, 2, 1, 23, 30)));
}

#[test]
fn cron_rejects_malformed_expression() {
    let request = json!({ "schedule": "cron", "cron": "not a cron", "nowMs": 0, "records": [] });
    assert!(evaluate(&request).is_none());
}

#[test]
fn window_activates_only_inside_the_interval() {
    let base = json!({
        "schedule": "window",
        "windowStartMinutes": 120,
        "windowEndMinutes": 240,
        "records": [],
    });
    // 03:00 inside [02:00, 04:00): active and never attempted → due.
    let mut inside = base.clone();
    inside["nowMs"] = json!(civil_ms(2024, 3, 1, 3, 0));
    let answer = evaluate_records(inside, &[(1, 0)]);
    assert_eq!(answer["windowActive"], json!(true));
    assert_eq!(answer["due"], json!([1]));

    // 05:00 outside; the last attempt was during today's window → not due, next open is tomorrow.
    let mut outside = base;
    outside["nowMs"] = json!(civil_ms(2024, 3, 1, 5, 0));
    let answer = evaluate_records(outside, &[(1, civil_ms(2024, 3, 1, 3, 30))]);
    assert_eq!(answer["windowActive"], json!(false));
    assert_eq!(answer["due"], json!([]));
    assert_eq!(answer["nextDueAt"], json!(civil_ms(2024, 3, 2, 2, 0)));
}

#[test]
fn overnight_window_wraps_midnight() {
    let base = json!({
        "schedule": "window",
        "windowStartMinutes": 23 * 60,
        "windowEndMinutes": 120,
        "records": [],
    });
    let mut after_midnight = base;
    after_midnight["nowMs"] = json!(civil_ms(2024, 3, 1, 0, 30));
    let answer = evaluate_records(after_midnight, &[(1, 0)]);
    assert_eq!(answer["windowActive"], json!(true));

    let mut evening = json!({
        "schedule": "window",
        "windowStartMinutes": 23 * 60,
        "windowEndMinutes": 120,
        "records": [],
    });
    evening["nowMs"] = json!(civil_ms(2024, 3, 1, 22, 0));
    let answer = evaluate_records(evening, &[(1, 0)]);
    assert_eq!(answer["windowActive"], json!(false));
    assert_eq!(answer["nextDueAt"], json!(civil_ms(2024, 3, 1, 23, 0)));
}

#[test]
fn pause_suppresses_until_expiry_then_runs_once() {
    let until = civil_ms(2024, 4, 1, 12, 0);
    let before = json!({
        "schedule": "pause",
        "pauseUntilMs": until,
        "nowMs": civil_ms(2024, 4, 1, 11, 0),
        "records": [],
    });
    let answer = evaluate_records(before, &[(1, 0)]);
    assert_eq!(answer["due"], json!([]));
    assert_eq!(answer["nextDueAt"], json!(until));

    let after = json!({
        "schedule": "pause",
        "pauseUntilMs": until,
        "nowMs": civil_ms(2024, 4, 1, 12, 5),
        "records": [],
    });
    let answer = evaluate_records(after.clone(), &[(1, until - HOUR)]);
    assert_eq!(answer["due"], json!([1]));

    // Already ran after expiry: nothing more to schedule.
    let answer = evaluate_records(after, &[(1, civil_ms(2024, 4, 1, 12, 1))]);
    assert_eq!(answer["due"], json!([]));
    assert_eq!(answer["nextDueAt"], Value::Null);
}

#[test]
fn evaluate_rules_aggregates_due_and_earliest_next() {
    let now = 100 * DAY + 9 * HOUR;
    let document = json!({
        "nowMs": now,
        "rules": [
            { "id": "a", "kind": "interval", "intervalHours": 24, "lastAttemptAt": 0 },
            { "id": "b", "kind": "interval", "intervalHours": 24, "lastAttemptAt": now - 23 * HOUR },
        ],
    });
    let answer = evaluate_rules(now, &document);
    assert_eq!(answer["due"], json!(["a"]));
    // The due rule contributes `now`; the not-yet-due rule contributes now+1h; the earliest wins.
    assert_eq!(answer["nextDueAt"], json!(now));
    assert_eq!(answer["windowActive"], json!(false));
}
