//! Raw SQLite rows to typed records, with the legacy defaults applied here and only here.

use serde_json::{json, Map, Value};

use crate::classify;
use crate::payload;

fn int(map: &Map<String, Value>, key: &str) -> i64 {
    payload::integer_in(map, key).unwrap_or(0)
}

fn text(map: &Map<String, Value>, key: &str) -> String {
    payload::text_in_or_empty(map, key)
}

fn optional(map: &Map<String, Value>, key: &str) -> Value {
    payload::nullable_text(map.get(key))
}

fn is_one(map: &Map<String, Value>, key: &str) -> bool {
    payload::integer_in(map, key) == Some(1)
}

fn dns_record(map: &Map<String, Value>) -> Value {
    let query_name = text(map, "queryName");
    let result = payload::text_in(map, "result").unwrap_or_else(|| "PASSED".to_owned());
    let message = payload::text_in(map, "message");
    let cached = is_one(map, "cached");
    let query_type = payload::integer_in(map, "queryType").unwrap_or(1);
    let connection = classify::dns_is_connection(query_type, &query_name, message.as_deref());
    json!({
        "timestamp": int(map, "timestamp"),
        "domain": query_name,
        "queryType": query_type,
        "result": result,
        "cached": cached,
        "message": message,
        "packageName": optional(map, "packageName"),
        "isConnection": connection,
        "logStatus": classify::dns_log_status(&result, connection, cached),
    })
}

fn dns_row(map: &Map<String, Value>) -> Value {
    let query_name = text(map, "queryName");
    let result = text(map, "result");
    let message = payload::text_in(map, "message");
    let query_type = int(map, "queryType");
    let connection = classify::dns_is_connection(query_type, &query_name, message.as_deref());
    let blocked = classify::dns_is_blocked(&result, message.as_deref());
    let rewritten = classify::dns_is_rewritten(&result, message.as_deref());
    json!({
        "id": int(map, "id"),
        "timestamp": int(map, "timestamp"),
        "queryName": query_name,
        "queryType": query_type,
        "result": result,
        "cached": is_one(map, "cached"),
        "message": message,
        "packageName": optional(map, "packageName"),
        "blockSubscriptionId": payload::integer_in(map, "blockSubscriptionId"),
        "isConnection": connection,
        "isBlocked": blocked,
        "isRewritten": rewritten,
        "status": classify::dns_request_status(&result, connection, blocked, rewritten),
        "messageFields": classify::dns_message(message.as_deref()),
    })
}

fn http_row(map: &Map<String, Value>) -> Value {
    let outcome = text(map, "outcome");
    json!({
        "id": int(map, "id"),
        "timestamp": int(map, "timestamp"),
        "packageName": text(map, "packageName"),
        "protocol": text(map, "protocol"),
        "outcome": outcome,
        "authority": optional(map, "authority"),
        "matchedRule": optional(map, "matchedRule"),
        "blockSubscriptionId": payload::integer_in(map, "blockSubscriptionId"),
        "status": classify::http_request_status(&outcome),
        "logStatus": classify::http_log_status(&outcome),
    })
}

fn race_row(map: &Map<String, Value>) -> Value {
    json!({
        "timestamp": int(map, "timestamp"),
        "queryName": text(map, "queryName"),
        "strategy": text(map, "strategy"),
        "providerCount": int(map, "providerCount"),
        "success": is_one(map, "success"),
        "elapsedMs": int(map, "elapsedMs"),
        "winnerProviderId": optional(map, "winnerProviderId"),
        "winnerElapsedMs": payload::integer_in(map, "winnerElapsedMs"),
        "message": optional(map, "message"),
    })
}

fn race_ranking(map: &Map<String, Value>) -> Value {
    let average = payload::number(&Value::Object(map.clone()), "avgElapsed").unwrap_or(0.0);
    json!({
        "providerId": text(map, "providerId"),
        "wins": int(map, "wins"),
        "averageLatencyMs": average.round() as i64,
        "averageElapsed": average,
    })
}

fn race_summary(map: &Map<String, Value>) -> Value {
    let average = payload::number(&Value::Object(map.clone()), "avgElapsed").unwrap_or(0.0);
    json!({
        "requests": int(map, "requests"),
        "successes": int(map, "successes"),
        "failures": int(map, "failures"),
        "averageLatencyMs": average.round() as i64,
        "averageElapsed": average,
    })
}

fn race_strategy(map: &Map<String, Value>) -> Value {
    json!({
        "strategy": text(map, "strategy"),
        "requests": int(map, "requests"),
        "successes": int(map, "successes"),
        "failures": int(map, "failures"),
        "averageElapsedMs": payload::number(&Value::Object(map.clone()), "avgElapsedMs").unwrap_or(0.0),
        "fallbackUses": int(map, "fallbackUses"),
        "fallbackSuccesses": int(map, "fallbackSuccesses"),
        "primaryWins": int(map, "primaryWins"),
    })
}

fn race_smart(map: &Map<String, Value>) -> Value {
    json!({
        "providerId": text(map, "providerId"),
        "selectedCount": int(map, "selectedCount"),
        "selectedSuccesses": int(map, "selectedSuccesses"),
        "averageElapsedMs": payload::number(&Value::Object(map.clone()), "avgSelectedElapsedMs").unwrap_or(0.0),
    })
}

fn bootstrap_stat(map: &Map<String, Value>) -> Value {
    json!({
        "id": text(map, "ipId"),
        "name": text(map, "ipName"),
        "ip": text(map, "ip"),
        "attempts": int(map, "attempts"),
        "successes": int(map, "successes"),
        "failures": int(map, "failures"),
        "averageElapsedMs": payload::nullable_text(map.get("avgElapsedMs")),
    })
}

fn cache_entry(map: &Map<String, Value>, now: i64) -> Value {
    let expires_at = int(map, "expiresAt");
    let remaining = expires_at - now;
    json!({
        "domain": text(map, "queryName"),
        "queryType": payload::integer_in(map, "queryType").unwrap_or(1),
        "expiresAt": expires_at,
        "hitCount": int(map, "hitCount"),
        "originalTtlSeconds": int(map, "originalTtlSeconds"),
        "responseSize": int(map, "responseSize"),
        "remainingTtlSeconds": if remaining <= 0 { 0 } else { remaining / 1000 },
    })
}

fn traffic_row(map: &Map<String, Value>) -> Value {
    json!({
        "date": text(map, "date"),
        "packageName": text(map, "package_name"),
        "appName": text(map, "app_name"),
        "txBytes": int(map, "tx_bytes"),
        "rxBytes": int(map, "rx_bytes"),
        "updatedAt": int(map, "updated_at"),
    })
}

fn subscription_row(map: &Map<String, Value>) -> Value {
    json!({
        "id": int(map, "id"),
        "name": text(map, "name"),
        "enabled": is_one(map, "enabled"),
    })
}

fn dns_daily(row: Option<&Map<String, Value>>) -> Value {
    let total = row.map_or(0, |map| int(map, "total"));
    let blocked = row.map_or(0, |map| int(map, "blocked"));
    let error = row.map_or(0, |map| int(map, "error"));
    let cached = row.map_or(0, |map| int(map, "cached"));
    let samples = row.map_or(0, |map| int(map, "samples"));
    let elapsed_total = row.map_or(0, |map| int(map, "elapsedTotal"));
    let passed = total - blocked - error;
    let lookups = passed + error;
    json!({
        "total": total,
        "passed": passed,
        "blocked": blocked,
        "error": error,
        "cached": cached,
        "averageLatencyMs": if samples == 0 { 0 } else { elapsed_total / samples },
        "latencySamples": samples,
        "cacheHitRate": if lookups == 0 { 0.0 } else { cached as f64 / lookups as f64 },
    })
}

fn http_daily(rows: &[Value]) -> Value {
    let mut by_outcome = serde_json::Map::new();
    let mut total = 0i64;
    for row in rows {
        let map = payload::object(row);
        let count = int(map, "count");
        by_outcome.insert(text(map, "outcome"), Value::from(count));
        total += count;
    }
    json!({ "total": total, "byOutcome": by_outcome })
}

/// Parses a page of rows; `kind` decides the shape. `nowMs` is only read by cache rows.
pub fn rows(request: &Value) -> Option<Value> {
    let kind = request.get("kind")?.as_str()?;
    let now = payload::integer_or(request, "nowMs", 0);
    if kind == "dns.daily" {
        let first = payload::list(request, "rows").first().map(payload::object);
        return Some(json!({ "items": [dns_daily(first)] }));
    }
    if kind == "http.daily" {
        return Some(json!({ "items": [http_daily(payload::list(request, "rows"))] }));
    }
    let mut items = Vec::new();
    for row in payload::list(request, "rows") {
        let map = payload::object(row);
        let parsed = match kind {
            "dns.record" => dns_record(map),
            "dns.row" => dns_row(map),
            "http.row" => http_row(map),
            "race.row" => race_row(map),
            "race.ranking" => race_ranking(map),
            "race.summary" => race_summary(map),
            "race.strategy" => race_strategy(map),
            "race.smart" => race_smart(map),
            "bootstrap.stat" => bootstrap_stat(map),
            "cache.entry" => cache_entry(map, now),
            "traffic.row" => traffic_row(map),
            "subscription.row" => subscription_row(map),
            "subscriptionHit" => json!({
                "id": payload::integer_in(map, "id"),
                "hits": int(map, "hits"),
            }),
            "packageCount" => json!({
                "packageName": text(map, "packageName"),
                "count": int(map, "count"),
            }),
            "cacheLastHit" => json!({
                "queryName": text(map, "queryName"),
                "queryType": payload::integer_in(map, "queryType").unwrap_or(1),
                "lastHitAt": payload::integer_in(map, "lastHitAt"),
            }),
            "count" => json!({ "n": int(map, "n") }),
            _ => return None,
        };
        items.push(parsed);
    }
    Some(json!({ "items": items }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_one(kind: &str, row: Value) -> Value {
        let request = json!({ "kind": kind, "rows": [row], "nowMs": 1_000 });
        let answer = rows(&request);
        assert!(answer.is_some(), "kind {kind} request {request}");
        answer.unwrap()["items"][0].clone()
    }

    #[test]
    fn dns_defaults_and_buckets() {
        let row = parse_one("dns.record", json!({}));
        assert_eq!(row["domain"], json!(""));
        assert_eq!(row["queryType"], json!(1));
        assert_eq!(row["result"], json!("PASSED"));
        assert_eq!(row["cached"], json!(false));
        assert_eq!(row["isConnection"], json!(false));
        assert_eq!(row["logStatus"], json!("passed"));

        let connection = parse_one(
            "dns.row",
            json!({ "queryName": "TCP 1.1.1.1:443", "queryType": 1, "result": "PASSED" }),
        );
        assert_eq!(connection["isConnection"], json!(true));
        assert_eq!(connection["status"], json!("bypassed"));

        let rewritten = parse_one(
            "dns.row",
            json!({ "queryName": "x", "queryType": 1, "result": "PASSED", "message": "matched rewrite rule" }),
        );
        assert_eq!(rewritten["isRewritten"], json!(true));
        assert_eq!(rewritten["status"], json!("rewritten"));
        assert_eq!(rewritten["messageFields"]["elapsedMs"], Value::Null);
    }

    #[test]
    fn http_and_race_flags() {
        let row = parse_one("http.row", json!({ "outcome": "rewritten" }));
        assert_eq!(row["status"], json!("rewritten"));
        assert_eq!(row["logStatus"], json!("passed"));
        let race = parse_one(
            "race.row",
            json!({ "success": 1, "winnerElapsedMs": 5, "winnerProviderId": "a" }),
        );
        assert_eq!(race["success"], json!(true));
        assert_eq!(race["winnerElapsedMs"], json!(5));
    }

    #[test]
    fn cache_ttl_uses_the_injected_clock() {
        let row = parse_one(
            "cache.entry",
            json!({ "expiresAt": 5_500, "queryType": null }),
        );
        assert_eq!(row["remainingTtlSeconds"], json!(4));
        assert_eq!(row["queryType"], json!(1));
        let expired = parse_one("cache.entry", json!({ "expiresAt": 500 }));
        assert_eq!(expired["remainingTtlSeconds"], json!(0));
    }

    #[test]
    fn traffic_and_subscription_rows() {
        let row = parse_one(
            "traffic.row",
            json!({ "package_name": "p", "tx_bytes": 2, "rx_bytes": 3 }),
        );
        assert_eq!(row["packageName"], json!("p"));
        assert_eq!(row["txBytes"], json!(2));
        let sub = parse_one("subscription.row", json!({ "id": 3, "enabled": 1 }));
        assert_eq!(sub["enabled"], json!(true));
    }
}
