//! Aggregates shared by the dashboard, request feed and statistics cards. Every ratio, fold and
//! sort order here is one of the legacy counting rules; labels stay in Dart.

use serde_json::{json, Map, Value};

use crate::classify;
use crate::payload;
use crate::util::{child, dart_cmp, i, items, n, percent, resolved_name, s};

/// The request feed: both tables merged newest-first, with the page window applied.
fn feed(request: &Value) -> Option<Value> {
    let limit = payload::integer_or(request, "limit", 0).max(0);
    let dns = items(request, "dns");
    let http = items(request, "http");
    let mut merged = Vec::with_capacity(dns.len() + http.len());
    for row in &dns {
        let query_type = i(row, "queryType");
        let query_name = s(row, "queryName");
        let result = s(row, "result");
        let message = payload::text_in(row, "message");
        let connection = classify::dns_is_connection(query_type, &query_name, message.as_deref());
        let blocked = classify::dns_is_blocked(&result, message.as_deref());
        let rewritten = classify::dns_is_rewritten(&result, message.as_deref());
        let fields = classify::dns_message(message.as_deref());
        merged.push(json!({
            "key": format!("dns-{}", i(row, "id")),
            "timestamp": i(row, "timestamp"),
            "source": "dns",
            "status": classify::dns_request_status(&result, connection, blocked, rewritten),
            "title": query_name,
            "packageName": payload::nullable_text(row.get("packageName")),
            "matchedRule": fields.get("blockedBy").cloned().unwrap_or(Value::Null),
            "message": message,
            "cached": payload::integer_in(row, "cached") == Some(1),
            "elapsedMs": fields.get("elapsedMs").cloned().unwrap_or(Value::Null),
            "blockSubscriptionId": payload::integer_in(row, "blockSubscriptionId"),
        }));
    }
    for row in &http {
        let outcome = s(row, "outcome");
        merged.push(json!({
            "key": format!("https-{}", i(row, "id")),
            "timestamp": i(row, "timestamp"),
            "source": "https",
            "status": classify::http_request_status(&outcome),
            "title": payload::text_in(row, "authority").unwrap_or_default(),
            "protocol": s(row, "protocol"),
            "packageName": s(row, "packageName"),
            "matchedRule": payload::nullable_text(row.get("matchedRule")),
            "message": Value::Null,
            "cached": false,
            "elapsedMs": Value::Null,
            "blockSubscriptionId": payload::integer_in(row, "blockSubscriptionId"),
        }));
    }
    merged.sort_by(|left, right| {
        right["timestamp"]
            .as_i64()
            .unwrap_or(0)
            .cmp(&left["timestamp"].as_i64().unwrap_or(0))
    });
    let has_more = dns.len() as i64 >= limit || http.len() as i64 >= limit;
    merged.truncate(limit as usize);
    Some(json!({ "items": merged, "hasMore": has_more }))
}

/// Request counts of both tables per package, most requests first and name as the tie-breaker.
fn app_counts(request: &Value) -> Option<Value> {
    let mut merged: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
    for row in items(request, "dns")
        .into_iter()
        .chain(items(request, "http"))
    {
        let name = s(row, "packageName");
        if name.is_empty() {
            continue;
        }
        *merged.entry(name).or_default() += i(row, "count");
    }
    let mut rows: Vec<(String, i64)> = merged.into_iter().collect();
    rows.sort_by(|left, right| {
        right
            .1
            .cmp(&left.1)
            .then_with(|| dart_cmp(&left.0, &right.0))
    });
    Some(json!({
        "items": rows
            .into_iter()
            .map(|(package_name, count)| json!({ "packageName": package_name, "count": count }))
            .collect::<Vec<Value>>(),
    }))
}

/// Race board for the dashboard: a compact summary plus named ranking rows.
fn race_board(request: &Value) -> Option<Value> {
    let summary = child(request, "summary");
    let entries = items(request, "ranking")
        .into_iter()
        .filter(|row| !s(row, "providerId").is_empty())
        .map(|row| {
            json!({
                "provider": resolved_name(request, &s(row, "providerId")),
                "wins": i(row, "wins"),
                "averageLatencyMs": i(row, "averageLatencyMs"),
            })
        })
        .collect::<Vec<Value>>();
    Some(json!({
        "summary": {
            "requests": i(summary, "requests"),
            "failures": i(summary, "failures"),
            "averageLatencyMs": i(summary, "averageLatencyMs"),
        },
        "entries": entries,
    }))
}

/// Full race page: summary, named ranking, per-strategy rows and smart-selection rows.
fn race_stats(request: &Value) -> Option<Value> {
    let summary = child(request, "summary");
    let entries = items(request, "ranking")
        .into_iter()
        .filter(|row| !s(row, "providerId").is_empty())
        .map(|row| {
            json!({
                "name": resolved_name(request, &s(row, "providerId")),
                "wins": i(row, "wins"),
                "averageLatencyMs": i(row, "averageLatencyMs"),
            })
        })
        .collect::<Vec<Value>>();
    let strategies = items(request, "strategy")
        .into_iter()
        .map(|row| {
            json!({
                "strategy": s(row, "strategy"),
                "requests": i(row, "requests"),
                "successes": i(row, "successes"),
                "failures": i(row, "failures"),
                "averageElapsedMs": n(row, "averageElapsedMs"),
                "fallbackUses": i(row, "fallbackUses"),
                "fallbackSuccesses": i(row, "fallbackSuccesses"),
                "primaryWins": i(row, "primaryWins"),
            })
        })
        .collect::<Vec<Value>>();
    let smart = items(request, "smart")
        .into_iter()
        .filter(|row| !s(row, "providerId").is_empty())
        .map(|row| {
            json!({
                "name": resolved_name(request, &s(row, "providerId")),
                "selectedCount": i(row, "selectedCount"),
                "selectedSuccesses": i(row, "selectedSuccesses"),
                "averageElapsedMs": n(row, "averageElapsedMs"),
            })
        })
        .collect::<Vec<Value>>();
    Some(json!({
        "summary": {
            "requests": i(summary, "requests"),
            "successes": i(summary, "successes"),
            "failures": i(summary, "failures"),
            "averageLatencyMs": i(summary, "averageLatencyMs"),
        },
        "entries": entries,
        "strategyStats": strategies,
        "smartSelections": smart,
    }))
}

pub(crate) fn bootstrap_summary(rows: &[&Map<String, Value>]) -> Value {
    let mut attempts = 0i64;
    let mut successes = 0i64;
    let mut failures = 0i64;
    let mut weighted = 0.0f64;
    for row in rows {
        let row_attempts = i(row, "attempts");
        attempts += row_attempts;
        successes += i(row, "successes");
        failures += i(row, "failures");
        weighted += n(row, "averageElapsedMs") * row_attempts as f64;
    }
    json!({
        "attempts": attempts,
        "successes": successes,
        "failures": failures,
        "averageElapsedMs": if attempts == 0 { 0.0 } else { weighted / attempts as f64 },
    })
}

fn bootstrap_stats(request: &Value) -> Option<Value> {
    let rows = items(request, "rows");
    let summary = bootstrap_summary(&rows);
    let ips = rows
        .iter()
        .map(|row| {
            json!({
                "name": s(row, "name"),
                "ip": s(row, "ip"),
                "attempts": i(row, "attempts"),
                "successes": i(row, "successes"),
                "averageElapsedMs": n(row, "averageElapsedMs"),
            })
        })
        .collect::<Vec<Value>>();
    let mut answer = summary;
    answer["ips"] = Value::Array(ips);
    Some(answer)
}

/// Subscription interception rows; `sortByName` distinguishes the page (hits, then name) from the
/// overview card (hits only).
fn subscription_stats(request: &Value) -> Option<Value> {
    let total = payload::integer_or(request, "total", 0);
    let subscriptions: std::collections::HashMap<i64, &Map<String, Value>> =
        items(request, "subscriptions")
            .into_iter()
            .map(|row| (i(row, "id"), row))
            .collect();
    let mut hits: std::collections::HashMap<i64, i64> = std::collections::HashMap::new();
    for row in items(request, "hits") {
        if let Some(id) = payload::integer_in(row, "id") {
            *hits.entry(id).or_default() += i(row, "hits");
        }
    }
    let sort_by_name = payload::flag_or(request, "sortByName", false);
    let mut ids: Vec<i64> = subscriptions
        .keys()
        .copied()
        .chain(hits.keys().copied())
        .collect();
    ids.sort_unstable();
    ids.dedup();
    let mut output = Vec::new();
    for id in ids {
        let subscription = subscriptions.get(&id);
        let count = hits.get(&id).copied().unwrap_or(0);
        output.push(json!({
            "id": id,
            "name": subscription.map(|row| s(row, "name")),
            "enabled": subscription.map(|row| i(row, "enabled") == 1).unwrap_or(false),
            "deleted": subscription.is_none(),
            "hits": count,
            "rate": percent(count, total),
        }));
    }
    if sort_by_name {
        output.sort_by(|left, right| {
            right["hits"]
                .as_i64()
                .unwrap_or(0)
                .cmp(&left["hits"].as_i64().unwrap_or(0))
                .then_with(|| {
                    dart_cmp(
                        left["name"].as_str().unwrap_or_default(),
                        right["name"].as_str().unwrap_or_default(),
                    )
                })
                .then_with(|| {
                    left["id"]
                        .as_i64()
                        .unwrap_or(0)
                        .cmp(&right["id"].as_i64().unwrap_or(0))
                })
        });
    } else {
        output.sort_by(|left, right| {
            right["hits"]
                .as_i64()
                .unwrap_or(0)
                .cmp(&left["hits"].as_i64().unwrap_or(0))
        });
    }
    Some(json!({ "totalRequests": total, "items": output }))
}

fn stats_requests(request: &Value) -> Option<Value> {
    let dns = child(request, "dns");
    let http = child(request, "http");
    let mut blocked = i(dns, "blocked");
    let http_value = Value::Object(http.clone());
    for (outcome, count) in child(&http_value, "byOutcome") {
        if classify::http_request_status(outcome) == "blocked" {
            blocked += count.as_i64().unwrap_or(0);
        }
    }
    Some(json!({
        "total": i(dns, "total") + i(http, "total"),
        "blocked": blocked,
        "cached": i(dns, "cached"),
    }))
}

fn stats_data(request: &Value) -> Option<Value> {
    let cached = payload::integer_or(request, "cached", 0);
    let average = payload::number(request, "avgResponseSize").unwrap_or(0.0);
    let saved = (cached as f64 * average).round() as i64;
    Some(json!({
        "saved": saved,
        "uploaded": payload::integer_or(request, "txBytes", 0),
        "downloaded": payload::integer_or(request, "rxBytes", 0),
    }))
}

fn traffic_snapshot(request: &Value) -> Option<Value> {
    let rows = payload::list(request, "rows");
    let mut tx = 0i64;
    let mut rx = 0i64;
    for row in rows {
        let map = payload::object(row);
        tx += i(map, "txBytes");
        rx += i(map, "rxBytes");
    }
    Some(json!({
        "rows": rows,
        "txBytes": tx,
        "rxBytes": rx,
        "totalBytes": tx + rx,
        "startDate": payload::text_or_empty(request, "startDate"),
        "endDate": payload::text_or_empty(request, "endDate"),
    }))
}

pub(crate) fn cache_hotspots(request: &Value) -> Option<Value> {
    let limit = payload::integer_or(request, "limit", 0).max(0);
    let rows = items(request, "rows");
    let items = rows
        .into_iter()
        .take(limit as usize)
        .map(|row| {
            json!({
                "queryName": s(row, "domain"),
                "queryType": i(row, "queryType"),
                "remainingSeconds": i(row, "remainingTtlSeconds"),
                "responseSize": i(row, "responseSize"),
                "hitCount": i(row, "hitCount"),
            })
        })
        .collect::<Vec<Value>>();
    Some(json!({ "items": items }))
}

pub fn derive(request: &Value) -> Option<Value> {
    match request.get("name")?.as_str()? {
        "feed" => feed(request),
        "appCounts" => app_counts(request),
        "race.board" => race_board(request),
        "race.stats" => race_stats(request),
        "bootstrap.stats" => bootstrap_stats(request),
        "subscription.stats" => subscription_stats(request),
        "stats.requests" => stats_requests(request),
        "stats.data" => stats_data(request),
        "traffic.snapshot" => traffic_snapshot(request),
        "cache.hotspots" => cache_hotspots(request),
        "overview" => crate::overview::overview(request),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feed_merges_and_takes() {
        let answer = derive(&json!({
            "name": "feed",
            "limit": 2,
            "dns": [
                { "id": 1, "timestamp": 10, "queryType": 1, "queryName": "a", "result": "PASSED" },
                { "id": 2, "timestamp": 30, "queryType": 1, "queryName": "b", "result": "BLOCKED", "message": "elapsed=7ms" }
            ],
            "http": [
                { "id": 3, "timestamp": 20, "authority": "h", "outcome": "rewritten" }
            ],
        }))
        .unwrap();
        assert_eq!(answer["hasMore"], json!(true));
        assert_eq!(answer["items"].as_array().unwrap().len(), 2);
        assert_eq!(answer["items"][0]["key"], json!("dns-2"));
        assert_eq!(answer["items"][1]["key"], json!("https-3"));
        assert_eq!(answer["items"][1]["title"], json!("h"));
    }

    #[test]
    fn app_counts_merge_and_sort() {
        let answer = derive(&json!({
            "name": "appCounts",
            "dns": [{ "packageName": "b", "count": 2 }, { "packageName": "a", "count": 2 }],
            "http": [{ "packageName": "b", "count": 1 }, { "packageName": "", "count": 9 }],
        }))
        .unwrap();
        assert_eq!(
            answer["items"],
            json!([
                { "packageName": "b", "count": 3 },
                { "packageName": "a", "count": 2 }
            ])
        );
    }

    #[test]
    fn race_board_resolves_names() {
        let answer = derive(&json!({
            "name": "race.board",
            "summary": { "requests": 3, "failures": 1, "averageLatencyMs": 5 },
            "ranking": [
                { "providerId": "a", "wins": 2, "averageLatencyMs": 4 },
                { "providerId": "", "wins": 9, "averageLatencyMs": 1 }
            ],
            "names": { "a": "Alpha" },
        }))
        .unwrap();
        assert_eq!(answer["summary"]["requests"], json!(3));
        assert_eq!(answer["entries"][0]["provider"], json!("Alpha"));
        assert_eq!(answer["entries"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn bootstrap_weighting() {
        let answer = derive(&json!({
            "name": "bootstrap.stats",
            "rows": [
                { "name": "a", "ip": "1", "attempts": 1, "successes": 1, "failures": 0, "averageElapsedMs": 10 },
                { "name": "b", "ip": "2", "attempts": 3, "successes": 2, "failures": 1, "averageElapsedMs": 20 }
            ],
        }))
        .unwrap();
        assert_eq!(answer["attempts"], json!(4));
        assert_eq!(answer["averageElapsedMs"], json!(17.5));
        assert_eq!(answer["ips"][1]["attempts"], json!(3));
    }

    #[test]
    fn subscription_rates() {
        let answer = derive(&json!({
            "name": "subscription.stats",
            "total": 10,
            "hits": [{ "id": 1, "hits": 4 }, { "id": 2, "hits": 6 }],
            "subscriptions": [{ "id": 1, "name": "A", "enabled": 1 }],
            "sortByName": true,
        }))
        .unwrap();
        assert_eq!(answer["items"][0]["id"], json!(2));
        assert_eq!(answer["items"][0]["deleted"], json!(true));
        assert_eq!(answer["items"][1]["rate"], json!(0.4));
    }

    #[test]
    fn stats_requests_adds_blocked_outcomes() {
        let answer = derive(&json!({
            "name": "stats.requests",
            "dns": { "total": 5, "blocked": 2, "cached": 1 },
            "http": { "total": 3, "byOutcome": { "blocked": 1, "invalid": 1, "allowed": 1 } },
        }))
        .unwrap();
        assert_eq!(answer, json!({ "total": 8, "blocked": 4, "cached": 1 }));
    }

    #[test]
    fn stats_data_rounds_saved_bytes() {
        let answer = derive(&json!({
            "name": "stats.data",
            "cached": 3,
            "avgResponseSize": 2.5,
            "txBytes": 4,
            "rxBytes": 5,
        }))
        .unwrap();
        assert_eq!(answer["saved"], json!(8));
    }
}
