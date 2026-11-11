//! The dashboard snapshot: one JSON answer the page renders without re-counting anything.

use serde_json::{json, Value};

use crate::classify;
use crate::derive::{bootstrap_summary, cache_hotspots};
use crate::payload;
use crate::util::{b, child, i, items, n, percent, resolved_name, s};

pub(crate) fn overview(request: &Value) -> Option<Value> {
    let filtered = payload::flag_or(request, "filteredMode", false);
    let off = payload::flag_or(request, "off", false);
    let dns = child(request, "dnsDaily");
    let http = child(request, "httpDaily");
    let mut http_passed = 0i64;
    let mut http_blocked = 0i64;
    let mut http_error = 0i64;
    let mut http_bypassed = 0i64;
    let http_value = Value::Object(http.clone());
    for (outcome, count) in child(&http_value, "byOutcome") {
        let count = count.as_i64().unwrap_or(0);
        if filtered && classify::http_outcome_is_passed(outcome) {
            continue;
        }
        match classify::http_log_status(outcome) {
            "passed" => http_passed += count,
            "filtered" => http_blocked += count,
            "bypassed" => http_bypassed += count,
            _ => http_error += count,
        }
    }
    let dns_passed = if filtered { 0 } else { i(dns, "passed") };
    let dns_cached = if filtered { 0 } else { i(dns, "cached") };
    let passed = dns_passed + http_passed;
    let blocked = i(dns, "blocked") + http_blocked;
    let error = i(dns, "error") + http_error;

    let bootstrap_rows = items(request, "bootstrapRows");
    let bootstrap = bootstrap_summary(&bootstrap_rows);
    let race_summary = child(request, "race");
    let total_requests =
        payload::integer_or(request, "dnsTotal", 0) + payload::integer_or(request, "httpTotal", 0);
    let subscription_rows = items(request, "subscriptions");
    let mut hits: std::collections::HashMap<i64, i64> = std::collections::HashMap::new();
    for row in items(request, "dnsHits")
        .into_iter()
        .chain(items(request, "httpHits"))
    {
        if let Some(id) = payload::integer_in(row, "id") {
            *hits.entry(id).or_default() += i(row, "hits");
        }
    }
    let mut blocks = Vec::new();
    for (id, count) in &hits {
        let subscription = subscription_rows.iter().find(|row| i(row, "id") == *id);
        blocks.push(json!({
            "id": id,
            "name": subscription.map(|row| s(row, "name")),
            "enabled": subscription.map(|row| b(row, "enabled")).unwrap_or(false),
            "deleted": subscription.is_none(),
            "hits": count,
            "rate": percent(*count, total_requests),
        }));
    }
    blocks.sort_by(|left, right| {
        right["hits"]
            .as_i64()
            .unwrap_or(0)
            .cmp(&left["hits"].as_i64().unwrap_or(0))
    });
    blocks.truncate(payload::integer_or(request, "subscriptionLimit", 5).max(0) as usize);

    let recent_limit = payload::integer_or(request, "recentLimit", 5).max(0);
    let mut recent = Vec::new();
    if !off {
        for row in items(request, "recentDns")
            .into_iter()
            .take(recent_limit as usize)
        {
            recent.push(json!({
                "source": "dns",
                "timestamp": i(row, "timestamp"),
                "logStatus": s(row, "logStatus"),
                "isConnection": b(row, "isConnection"),
                "domain": s(row, "domain"),
                "queryType": i(row, "queryType"),
                "result": s(row, "result"),
                "cached": b(row, "cached"),
                "message": payload::text_in(row, "message"),
                "packageName": payload::nullable_text(row.get("packageName")),
            }));
        }
        for row in items(request, "recentHttp") {
            if filtered && classify::http_outcome_is_passed(&s(row, "outcome")) {
                continue;
            }
            recent.push(json!({
                "source": "https",
                "timestamp": i(row, "timestamp"),
                "logStatus": s(row, "logStatus"),
                "authority": payload::text_in(row, "authority").unwrap_or_default(),
                "protocol": s(row, "protocol"),
                "packageName": s(row, "packageName"),
                "matchedRule": payload::nullable_text(row.get("matchedRule")),
                "outcome": s(row, "outcome"),
            }));
        }
        recent.sort_by(|left, right| {
            right["timestamp"]
                .as_i64()
                .unwrap_or(0)
                .cmp(&left["timestamp"].as_i64().unwrap_or(0))
        });
        recent.truncate(recent_limit as usize);
    }

    let top_limit = payload::integer_or(request, "topLimit", 8).max(0) as usize;
    let winners = items(request, "raceRanking")
        .into_iter()
        .filter(|row| !s(row, "providerId").is_empty())
        .take(top_limit)
        .map(|row| {
            json!({
                "name": resolved_name(request, &s(row, "providerId")),
                "wins": i(row, "wins"),
                "averageElapsedMs": n(row, "averageElapsed"),
            })
        })
        .collect::<Vec<Value>>();
    let bootstrap_ips = bootstrap_rows
        .iter()
        .take(top_limit)
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

    Some(json!({
        "breakdown": {
            "total": passed + blocked + error + http_bypassed,
            "passed": passed,
            "blocked": blocked,
            "error": error,
            "bypassed": http_bypassed,
            "cached": dns_cached,
        },
        "quality": {
            "averageLatencyMs": if i(dns, "latencySamples") == 0 { Value::Null } else { Value::from(n(dns, "averageLatencyMs")) },
            "latencySamples": i(dns, "latencySamples"),
            "cacheHitRate": if filtered { 0.0 } else { n(dns, "cacheHitRate") },
        },
        "race": {
            "requests": i(race_summary, "requests"),
            "successes": i(race_summary, "successes"),
            "averageElapsedMs": n(race_summary, "averageElapsed"),
        },
        "bootstrap": bootstrap,
        "offMode": {
            "cacheEntries": payload::integer_or(request, "cacheEntries", 0),
            "cacheHits": payload::integer_or(request, "cacheHits", 0),
            "raceRequests": i(race_summary, "requests"),
            "bootstrapAttempts": bootstrap["attempts"].as_i64().unwrap_or(0),
        },
        "recent": recent,
        "cacheHotspots": cache_hotspots(&json!({
            "rows": payload::list(request, "cacheRows"),
            "limit": payload::integer_or(request, "recentCacheLimit", 5),
        }))?["items"].clone(),
        "raceWinners": winners,
        "bootstrapIps": bootstrap_ips,
        "subscriptionBlocks": blocks,
    }))
}
