use serde_json::{json, Value};

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
