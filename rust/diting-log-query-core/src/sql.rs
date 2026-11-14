//! Read-only SQL for the log tables. The statements are the legacy ones: ordering, status clauses
//! and the `elapsed=` sub-string arithmetic are part of the meaning, not formatting.

use serde_json::{json, Value};

use crate::payload;

struct Plan {
    sql: String,
    args: Vec<Value>,
}

impl Plan {
    fn new(sql: impl Into<String>) -> Self {
        Self {
            sql: sql.into(),
            args: Vec::new(),
        }
    }

    fn arg(mut self, value: Value) -> Self {
        self.args.push(value);
        self
    }

    fn answer(self) -> Value {
        json!({ "sql": self.sql, "args": self.args })
    }
}

fn limit_of(request: &Value, fallback: i64) -> i64 {
    let limit = payload::integer_or(request, "limit", fallback);
    if limit < 0 {
        0
    } else {
        limit
    }
}

fn since_arg(request: &Value) -> Option<i64> {
    payload::integer(request, "since")
}

/// Inclusive upper bound on `timestamp`, for cursor paging of the merged request feed.
///
/// The feed interleaves `dns_log` and `http_request_log` by timestamp, so an `OFFSET` applied to
/// each table separately would duplicate or skip rows at the seam. A cursor on the merged key is
/// the only cheap option: each page reads at most `limit` rows per table no matter how deep the
/// user has scrolled, where the old `LIMIT page * 50` widened the window and re-read every earlier
/// row on every page.
fn before_arg(request: &Value) -> Option<i64> {
    payload::integer(request, "before")
}

/// Inclusive upper bound on `timestamp`, used by the export plans (a bounded window rather than a
/// paging cursor).
fn until_arg(request: &Value) -> Option<i64> {
    payload::integer(request, "until")
}

fn like_pattern(query: &str) -> String {
    format!("%{}%", query.trim().to_lowercase())
}

fn dns_status_clause(status: &str) -> Option<&'static str> {
    match status {
        "passed" => Some(
            " AND result = 'PASSED' AND queryType > 0 AND queryName NOT LIKE 'TCP %' \
AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR (message NOT \
LIKE '%blocked_by=connection%' AND message NOT LIKE \
'%blocked_by=rewrite=%' AND message NOT LIKE '%matched rewrite \
rule%' AND message NOT LIKE '%复写%' AND message NOT LIKE '%覆写%'))",
        ),
        "rewritten" => Some(
            " AND (result = 'REWRITTEN' OR message LIKE '%blocked_by=rewrite=%' OR \
message LIKE '%matched rewrite rule%' OR message LIKE '%复写%' OR \
message LIKE '%覆写%') AND queryType > 0 AND queryName NOT LIKE \
'TCP %' AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR \
message NOT LIKE '%blocked_by=connection%')",
        ),
        "blocked" => Some(
            " AND (result = 'BLOCKED' OR message LIKE '%blocked_by=firewall:%') \
AND (message IS NULL OR (message NOT LIKE '%blocked_by=rewrite=%' \
AND message NOT LIKE '%matched rewrite rule%' AND message NOT LIKE \
'%复写%' AND message NOT LIKE '%覆写%'))",
        ),
        "error" => Some(
            " AND result = 'ERROR' AND queryType > 0 AND queryName NOT LIKE 'TCP %' \
AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR (message NOT \
LIKE '%blocked_by=connection%' AND message NOT LIKE \
'%blocked_by=rewrite=%' AND message NOT LIKE '%matched rewrite \
rule%' AND message NOT LIKE '%复写%' AND message NOT LIKE '%覆写%'))",
        ),
        "bypassed" => Some(
            " AND (queryType = 0 OR queryName LIKE 'TCP %' OR queryName LIKE \
'UDP %' OR message LIKE '%blocked_by=connection%') AND (message IS \
NULL OR message NOT LIKE '%blocked_by=firewall:%')",
        ),
        _ => None,
    }
}

fn http_status_clause(status: &str) -> Option<&'static str> {
    match status {
        "passed" => Some(" AND outcome = 'allowed'"),
        "rewritten" => Some(" AND outcome = 'rewritten'"),
        "blocked" => Some(" AND outcome IN ('blocked', 'invalid')"),
        "error" => Some(
            " AND outcome NOT IN ('allowed', 'rewritten', 'blocked', 'invalid', \
'passthrough', 'bypassed', 'unsupported_protocol', \
'resource_bypass')",
        ),
        "bypassed" => Some(
            " AND outcome IN ('passthrough', 'bypassed', 'unsupported_protocol', \
'resource_bypass')",
        ),
        _ => None,
    }
}

fn table_of(request: &Value) -> Option<&'static str> {
    match request.get("table").and_then(Value::as_str) {
        Some("http") => Some("http_request_log"),
        _ => Some("dns_log"),
    }
}

/// Builds one statement; `None` means the query name is unknown.
pub fn plan(request: &Value) -> Option<Value> {
    let query = request.get("name")?.as_str()?;
    let answer = match query {
        "dns.recent" => Plan::new(format!(
            "SELECT * FROM dns_log ORDER BY timestamp DESC, id DESC LIMIT {}",
            limit_of(request, 200)
        ))
        .answer(),
        "dns.query.countByPackage" => Plan::new(
            "SELECT packageName, COUNT(*) AS count FROM dns_log \
WHERE packageName IS NOT NULL AND packageName != '' \
GROUP BY packageName",
        )
        .answer(),
        "dns.query.recent" => {
            let mut plan = Plan::new("SELECT * FROM dns_log WHERE 1=1");
            if let Some(package) = payload::text(request, "packageName") {
                plan = plan.arg(Value::String(package));
                plan.sql.push_str(" AND packageName = ?");
            }
            let query_text = payload::text_or_empty(request, "query");
            if !query_text.trim().is_empty() {
                let pattern = Value::String(like_pattern(&query_text));
                plan = plan.arg(pattern.clone()).arg(pattern.clone()).arg(pattern);
                plan.sql.push_str(
                    " AND (queryName LIKE ? OR packageName LIKE ? \
OR message LIKE ?)",
                );
            }
            let status = payload::text_or_empty(request, "status");
            if let Some(clause) = dns_status_clause(&status) {
                plan.sql.push_str(clause);
            }
            if let Some(before) = before_arg(request) {
                plan = plan.arg(Value::from(before));
                plan.sql.push_str(" AND timestamp <= ?");
            }
            // `id` breaks timestamp ties so a cursor page boundary cannot drop or repeat a row.
            plan.sql.push_str(&format!(
                " ORDER BY timestamp DESC, id DESC LIMIT {}",
                limit_of(request, 200)
            ));
            plan.answer()
        }
        "dns.daily" => Plan::new(
            "SELECT COUNT(*) AS total, \
COALESCE(SUM(result = 'BLOCKED'), 0) AS blocked, \
COALESCE(SUM(result = 'ERROR'), 0) AS error, \
COALESCE(SUM(result NOT IN ('BLOCKED', 'ERROR') AND cached = 1), 0) AS cached, \
COALESCE(SUM(e IS NOT NULL), 0) AS samples, \
COALESCE(SUM(e), 0) AS elapsedTotal \
FROM (SELECT result, cached, \
CASE WHEN p > 0 AND substr(message, p + 8, 1) BETWEEN '0' AND '9' \
THEN CAST(substr(message, p + 8) AS INTEGER) END AS e \
FROM (SELECT result, cached, message, instr(message, 'elapsed=') AS p \
FROM dns_log WHERE timestamp >= ?))",
        )
        .arg(Value::from(since_arg(request).unwrap_or(0)))
        .answer(),
        "dns.blockedErrors.recent" => Plan::new(format!(
            "SELECT * FROM dns_log WHERE result IN ('BLOCKED', 'ERROR') \
ORDER BY timestamp DESC, id DESC LIMIT {}",
            limit_of(request, 5)
        ))
        .answer(),
        // R2 命中统计：按域名聚合被拦截次数（Top 排行）。
        "dns.topDomains" => Plan::new(
            "SELECT queryName AS domain, COUNT(*) AS count FROM dns_log \
WHERE result = 'BLOCKED' AND timestamp >= ? \
GROUP BY queryName ORDER BY count DESC, domain ASC LIMIT ?",
        )
        .arg(Value::from(since_arg(request).unwrap_or(0)))
        .arg(Value::from(limit_of(request, 20)))
        .answer(),
        // R2 归因：从 message 的 `blocked_by=<原因>` 里抽出原因并聚合。`blocked_by=` 占 11 个
        // 字符；原因到下一个空格为止，没有空格则取到结尾。没有该字段的行归为 `unknown`。
        "dns.topReasons" => Plan::new(
            "SELECT reason, COUNT(*) AS count FROM (SELECT CASE \
WHEN instr(message, 'blocked_by=') > 0 THEN CASE \
WHEN instr(substr(message, instr(message, 'blocked_by=') + 11), ' ') > 0 THEN \
substr(message, instr(message, 'blocked_by=') + 11, \
instr(substr(message, instr(message, 'blocked_by=') + 11), ' ') - 1) \
ELSE substr(message, instr(message, 'blocked_by=') + 11) END \
ELSE 'unknown' END AS reason \
FROM dns_log WHERE result = 'BLOCKED' AND timestamp >= ?) \
WHERE reason != '' GROUP BY reason ORDER BY count DESC, reason ASC LIMIT ?",
        )
        .arg(Value::from(since_arg(request).unwrap_or(0)))
        .arg(Value::from(limit_of(request, 20)))
        .answer(),
        // R2 总拦截数（与排行同一时间窗），用于页面概览的分母。
        "dns.blockedCount" => Plan::new(
            "SELECT COUNT(*) AS n FROM dns_log WHERE result = 'BLOCKED' AND timestamp >= ?",
        )
        .arg(Value::from(since_arg(request).unwrap_or(0)))
        .answer(),
        "http.query.countByPackage" => Plan::new(
            "SELECT packageName, COUNT(*) AS count FROM http_request_log \
WHERE packageName != '' GROUP BY packageName",
        )
        .answer(),
        "http.query.recent" => {
            let mut plan = Plan::new("SELECT * FROM http_request_log WHERE 1=1");
            if let Some(package) = payload::text(request, "packageName") {
                plan = plan.arg(Value::String(package));
                plan.sql.push_str(" AND packageName = ?");
            }
            let query_text = payload::text_or_empty(request, "query");
            if !query_text.trim().is_empty() {
                let pattern = Value::String(like_pattern(&query_text));
                plan = plan.arg(pattern.clone()).arg(pattern.clone()).arg(pattern);
                plan.sql.push_str(
                    " AND (authority LIKE ? OR packageName LIKE ? \
OR matchedRule LIKE ?)",
                );
            }
            let status = payload::text_or_empty(request, "status");
            if let Some(clause) = http_status_clause(&status) {
                plan.sql.push_str(clause);
            }
            if let Some(before) = before_arg(request) {
                plan = plan.arg(Value::from(before));
                plan.sql.push_str(" AND timestamp <= ?");
            }
            plan.sql.push_str(&format!(
                " ORDER BY timestamp DESC, id DESC LIMIT {}",
                limit_of(request, 200)
            ));
            plan.answer()
        }
        "dns.query.export" | "http.query.export" => {
            let is_http = query == "http.query.export";
            let table = if is_http {
                "http_request_log"
            } else {
                "dns_log"
            };
            let mut plan = Plan::new(format!("SELECT * FROM {table} WHERE 1=1"));
            let packages: Vec<&str> = payload::list(request, "packages")
                .iter()
                .filter_map(Value::as_str)
                .filter(|package| !package.is_empty())
                .collect();
            if !packages.is_empty() {
                let placeholders = std::iter::repeat_n("?", packages.len())
                    .collect::<Vec<_>>()
                    .join(", ");
                plan.sql
                    .push_str(&format!(" AND packageName IN ({placeholders})"));
                for package in packages {
                    plan = plan.arg(Value::String(package.to_owned()));
                }
            }
            let status = payload::text_or_empty(request, "status");
            let clause = if is_http {
                http_status_clause(&status)
            } else {
                dns_status_clause(&status)
            };
            if let Some(clause) = clause {
                plan.sql.push_str(clause);
            }
            if let Some(since) = since_arg(request) {
                plan = plan.arg(Value::from(since));
                plan.sql.push_str(" AND timestamp >= ?");
            }
            if let Some(until) = until_arg(request) {
                plan = plan.arg(Value::from(until));
                plan.sql.push_str(" AND timestamp <= ?");
            }
            // The whole table is never read: a bounded window plus a hard cap keeps memory flat.
            plan.sql.push_str(&format!(
                " ORDER BY timestamp DESC, id DESC LIMIT {}",
                limit_of(request, 1000)
            ));
            plan.answer()
        }
        "http.daily" => Plan::new(
            "SELECT outcome, COUNT(*) AS count FROM http_request_log \
WHERE timestamp >= ? GROUP BY outcome",
        )
        .arg(Value::from(since_arg(request).unwrap_or(0)))
        .answer(),
        "race.recent" => Plan::new(format!(
            "SELECT * FROM dns_race_log ORDER BY timestamp DESC, id DESC LIMIT {}",
            limit_of(request, 100)
        ))
        .answer(),
        "race.ranking" => {
            let mut plan = Plan::new(
                "SELECT winnerProviderId AS providerId, \
COUNT(*) AS wins, \
AVG(CASE WHEN winnerElapsedMs IS NOT NULL THEN winnerElapsedMs END) \
AS avgElapsed FROM dns_race_log \
WHERE success = 1 AND winnerProviderId IS NOT NULL",
            );
            if let Some(since) = since_arg(request) {
                plan = plan.arg(Value::from(since));
                plan.sql.push_str(" AND timestamp >= ?");
            }
            plan.sql
                .push_str(" GROUP BY winnerProviderId ORDER BY wins DESC, avgElapsed ASC LIMIT ?");
            plan.arg(Value::from(limit_of(request, 20))).answer()
        }
        "race.summary" => {
            let mut plan = Plan::new(
                "SELECT COUNT(*) AS requests, \
SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) AS successes, \
SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) AS failures, \
AVG(elapsedMs) AS avgElapsed FROM dns_race_log",
            );
            if let Some(since) = since_arg(request) {
                plan = plan.arg(Value::from(since));
                plan.sql.push_str(" WHERE timestamp >= ?");
            }
            plan.answer()
        }
        "race.strategy" => {
            let mut plan = Plan::new(
                "SELECT strategy, COUNT(*) AS requests, \
SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) AS successes, \
SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) AS failures, \
AVG(elapsedMs) AS avgElapsedMs, \
SUM(CASE WHEN fallbackUsed = 1 THEN 1 ELSE 0 END) AS fallbackUses, \
SUM(CASE WHEN fallbackSuccess = 1 THEN 1 ELSE 0 END) AS fallbackSuccesses, \
SUM(CASE WHEN selectedProviderId IS NOT NULL \
AND winnerProviderId = selectedProviderId AND success = 1 \
THEN 1 ELSE 0 END) AS primaryWins FROM dns_race_log",
            );
            if let Some(since) = since_arg(request) {
                plan = plan.arg(Value::from(since));
                plan.sql.push_str(" WHERE timestamp >= ?");
            }
            plan.sql.push_str(" GROUP BY strategy ORDER BY strategy");
            plan.answer()
        }
        "race.smart" => {
            let strategy = payload::text_or_empty(request, "strategy");
            let strategy = if strategy.is_empty() {
                "smart_prediction".to_owned()
            } else {
                strategy
            };
            let mut plan = Plan::new(
                "SELECT selectedProviderId AS providerId, \
COUNT(*) AS selectedCount, \
SUM(CASE WHEN fallbackUsed = 0 AND winnerProviderId = selectedProviderId \
AND success = 1 THEN 1 ELSE 0 END) AS selectedSuccesses, \
AVG(selectedElapsedMs) AS avgSelectedElapsedMs FROM dns_race_log \
WHERE selectedProviderId IS NOT NULL AND strategy = ?",
            )
            .arg(Value::String(strategy));
            if let Some(since) = since_arg(request) {
                plan = plan.arg(Value::from(since));
                plan.sql.push_str(" AND timestamp >= ?");
            }
            plan.sql
                .push_str(" GROUP BY selectedProviderId ORDER BY selectedCount DESC");
            plan.answer()
        }
        "bootstrap.recent" => Plan::new(
            "SELECT ipId, MAX(ipName) AS ipName, MAX(ip) AS ip, COUNT(*) AS attempts, \
COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS successes, \
COALESCE(SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END), 0) AS failures, \
AVG(elapsedMs) AS avgElapsedMs FROM bootstrap_log WHERE timestamp >= ? \
GROUP BY ipId ORDER BY attempts DESC",
        )
        .arg(Value::from(since_arg(request).unwrap_or(0)))
        .answer(),
        "cache.entries" => Plan::new(
            "SELECT queryName, queryType, expiresAt, hitCount, originalTtlSeconds, \
responseSize FROM dns_cache WHERE expiresAt > ? \
ORDER BY hitCount DESC, expiresAt DESC LIMIT ?",
        )
        .arg(Value::from(payload::integer_or(request, "now", 0)))
        .arg(Value::from(limit_of(request, 200)))
        .answer(),
        "cache.count" => Plan::new("SELECT COUNT(*) AS n FROM dns_cache WHERE expiresAt > ?")
            .arg(Value::from(payload::integer_or(request, "now", 0)))
            .answer(),
        "cache.hits" => Plan::new("SELECT COALESCE(SUM(hitCount), 0) AS n FROM dns_cache").answer(),
        "cache.lastHit" => Plan::new(
            "SELECT queryName, queryType, lastHitAt FROM dns_cache WHERE expiresAt > ? \
ORDER BY hitCount DESC, expiresAt DESC LIMIT ?",
        )
        .arg(Value::from(payload::integer_or(request, "now", 0)))
        .arg(Value::from(limit_of(request, 200)))
        .answer(),
        "cache.avgSize" => Plan::new("SELECT AVG(responseSize) AS n FROM dns_cache").answer(),
        "traffic.byDate" => Plan::new(
            "SELECT * FROM app_traffic_daily WHERE date = ? \
ORDER BY (tx_bytes + rx_bytes) DESC",
        )
        .arg(Value::String(payload::text_or_empty(request, "date")))
        .answer(),
        "traffic.dateRange" => Plan::new(
            "SELECT min(date) as date, package_name, max(app_name) as app_name, \
sum(tx_bytes) as tx_bytes, sum(rx_bytes) as rx_bytes, \
max(updated_at) as updated_at FROM app_traffic_daily \
WHERE date >= ? AND date <= ? GROUP BY package_name \
ORDER BY (sum(tx_bytes) + sum(rx_bytes)) DESC",
        )
        .arg(Value::String(payload::text_or_empty(request, "startDate")))
        .arg(Value::String(payload::text_or_empty(request, "endDate")))
        .answer(),
        "traffic.all" => Plan::new(
            "SELECT min(date) as date, package_name, max(app_name) as app_name, \
sum(tx_bytes) as tx_bytes, sum(rx_bytes) as rx_bytes, \
max(updated_at) as updated_at FROM app_traffic_daily \
GROUP BY package_name ORDER BY (sum(tx_bytes) + sum(rx_bytes)) DESC",
        )
        .answer(),
        "subscription.total" => {
            let table = table_of(request)?;
            let mut plan = Plan::new(format!("SELECT COUNT(*) AS n FROM {table}"));
            if let Some(since) = since_arg(request) {
                plan = plan.arg(Value::from(since));
                plan.sql.push_str(" WHERE timestamp >= ?");
            }
            plan.answer()
        }
        "subscription.hits" => {
            let table = table_of(request)?;
            let mut plan = if table == "http_request_log" {
                Plan::new(
                    "SELECT blockSubscriptionId AS id, COUNT(*) AS hits \
FROM http_request_log WHERE outcome IN ('blocked', 'invalid') \
AND blockSubscriptionId IS NOT NULL",
                )
            } else {
                Plan::new(
                    "SELECT blockSubscriptionId AS id, COUNT(*) AS hits FROM dns_log \
WHERE result = 'BLOCKED' AND blockSubscriptionId IS NOT NULL",
                )
            };
            if let Some(since) = since_arg(request) {
                plan = plan.arg(Value::from(since));
                plan.sql.push_str(" AND timestamp >= ?");
            }
            plan.sql.push_str(" GROUP BY blockSubscriptionId");
            plan.answer()
        }
        "subscription.rows" => Plan::new("SELECT id, name, enabled FROM subscription").answer(),
        _ => return None,
    };
    Some(answer)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan_of(request: Value) -> Plan {
        let answer = plan(&request).unwrap();
        Plan {
            sql: answer["sql"].as_str().unwrap().to_owned(),
            args: answer["args"].as_array().unwrap().clone(),
        }
    }

    #[test]
    fn hit_ranking_plans_group_blocked_rows() {
        let domains = plan_of(json!({ "name": "dns.topDomains", "since": 5, "limit": 10 }));
        assert!(domains.sql.contains("result = 'BLOCKED'"));
        assert!(domains.sql.contains("GROUP BY queryName"));
        assert!(domains.sql.ends_with("LIMIT ?"));
        assert_eq!(domains.args, vec![json!(5), json!(10)]);

        // No `since` binds epoch 0, so "all time" is one code path.
        let reasons = plan_of(json!({ "name": "dns.topReasons", "limit": 20 }));
        assert!(reasons.sql.contains("instr(message, 'blocked_by=')"));
        assert!(reasons.sql.contains("GROUP BY reason"));
        assert_eq!(reasons.args[0], json!(0));

        let total = plan_of(json!({ "name": "dns.blockedCount", "since": 7 }));
        assert!(total.sql.contains("COUNT(*) AS n"));
        assert_eq!(total.args, vec![json!(7)]);
    }

    #[test]
    fn dns_filters_keep_their_order() {
        let plan = plan_of(json!({
            "name": "dns.query.recent",
            "limit": 50,
            "status": "blocked",
            "query": " Ads ",
            "packageName": "com.x",
        }));
        assert!(plan.sql.starts_with(
            "SELECT * FROM dns_log WHERE 1=1 AND packageName = ? AND (queryName LIKE ?"
        ));
        assert!(plan
            .sql
            .contains(" AND (result = 'BLOCKED' OR message LIKE"));
        assert!(plan
            .sql
            .ends_with("ORDER BY timestamp DESC, id DESC LIMIT 50"));
        assert_eq!(plan.args[0], json!("com.x"));
        assert_eq!(plan.args[1], json!("%ads%"));
        assert_eq!(plan.args.len(), 4);
    }

    #[test]
    fn before_cursor_is_the_last_bound_argument() {
        let plan = plan_of(json!({
            "name": "dns.query.recent",
            "limit": 50,
            "packageName": "com.x",
            "before": 1_700_000_000_000i64,
        }));
        assert!(plan
            .sql
            .ends_with("AND timestamp <= ? ORDER BY timestamp DESC, id DESC LIMIT 50"));
        // packageName first, cursor last: the placeholder order has to match the clause order.
        assert_eq!(plan.args, vec![json!("com.x"), json!(1_700_000_000_000i64)]);
    }

    #[test]
    fn https_cursor_keeps_the_filter_args_in_front() {
        let plan = plan_of(json!({
            "name": "http.query.recent",
            "limit": 50,
            "query": "Example",
            "status": "blocked",
            "before": 42,
        }));
        assert!(plan
            .sql
            .ends_with("AND timestamp <= ? ORDER BY timestamp DESC, id DESC LIMIT 50"));
        assert_eq!(plan.args.len(), 4);
        assert_eq!(plan.args[3], json!(42));
    }

    #[test]
    fn no_cursor_leaves_the_statement_unchanged() {
        let plan = plan_of(json!({ "name": "dns.query.recent", "limit": 50 }));
        assert!(!plan.sql.contains("timestamp <="));
        assert!(plan.args.is_empty());
        assert!(plan
            .sql
            .ends_with("ORDER BY timestamp DESC, id DESC LIMIT 50"));
    }

    #[test]
    fn negative_limits_become_zero() {
        let plan = plan_of(json!({ "name": "dns.recent", "limit": -1 }));
        assert!(plan.sql.ends_with("LIMIT 0"));
    }

    #[test]
    fn optional_since_changes_the_args() {
        let without = plan_of(json!({ "name": "race.summary" }));
        assert!(!without.sql.contains("timestamp"));
        assert!(without.args.is_empty());
        let with = plan_of(json!({ "name": "race.summary", "since": 7 }));
        assert!(with.sql.ends_with("WHERE timestamp >= ?"));
        assert_eq!(with.args, vec![json!(7)]);
    }

    #[test]
    fn http_tables_are_chosen_by_a_whitelist() {
        let dns = plan_of(json!({ "name": "subscription.hits", "table": "http" }));
        assert!(dns.sql.contains("http_request_log"));
        assert!(dns.sql.contains("outcome IN ('blocked', 'invalid')"));
        let fallback = plan_of(json!({ "name": "subscription.hits" }));
        assert!(fallback.sql.contains("FROM dns_log"));
    }

    #[test]
    fn export_plans_carry_every_filter_in_order() {
        let plan = plan_of(json!({
            "name": "dns.query.export",
            "limit": 500,
            "status": "blocked",
            "packages": ["com.a", "com.b"],
            "since": 100,
            "until": 200,
        }));
        assert!(plan
            .sql
            .starts_with("SELECT * FROM dns_log WHERE 1=1 AND packageName IN (?, ?)"));
        assert!(plan.sql.contains("result = 'BLOCKED'"));
        assert!(plan.sql.ends_with(
            "AND timestamp >= ? AND timestamp <= ? \
ORDER BY timestamp DESC, id DESC LIMIT 500"
        ));
        // Placeholder order has to match clause order: packages, then since, then until.
        assert_eq!(
            plan.args,
            vec![json!("com.a"), json!("com.b"), json!(100), json!(200)]
        );
    }

    #[test]
    fn export_plan_without_packages_or_status_only_bounds_time() {
        let plan = plan_of(json!({
            "name": "http.query.export",
            "limit": 10,
            "since": 5,
        }));
        assert!(plan
            .sql
            .starts_with("SELECT * FROM http_request_log WHERE 1=1 AND timestamp >= ?"));
        assert!(!plan.sql.contains("packageName IN"));
        assert_eq!(plan.args, vec![json!(5)]);
    }

    #[test]
    fn unknown_queries_are_rejected() {
        assert!(plan(&json!({ "name": "nope" })).is_none());
        assert!(plan(&json!({})).is_none());
    }
}
