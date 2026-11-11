//! Statement plans: what an import queues per rule, how a source is swept, and how a table is paged.
//!
//! The app runs every statement inside its own transaction/batch; what is queued, in which order and
//! what it dedupes against is decided here. Dedupe is an explicit `WHERE NOT EXISTS` rather than
//! `INSERT OR IGNORE`: legacy databases have no unique index, and a second copy of the predicate in
//! Dart is exactly how the two sides would drift.

use serde_json::{json, Map, Value};

use crate::identity::{identity, Flavor};
use crate::probe::{flag, integer, list, text};

/// Every rule table and its provenance table, in the order a sweep walks them.
pub const SOURCE_TABLES: [(&str, &str); 4] = [
    ("block_rule", "block_rule_source"),
    ("allow_rule", "allow_rule_source"),
    ("rewrite_rule", "rewrite_rule_source"),
    ("go_url_rule", "go_url_rule_source"),
];

/// Sources a user sweep may delete; `preset` and `sub_*` are kept.
pub const USER_SOURCES: [&str; 3] = ["useradd", "local_import", "local_hosts"];

/// Rows per orphan-delete transaction: small enough that the write lock is released often.
pub const ORPHAN_PAGE_SIZE: i64 = 2000;

fn step(sql: String, args: Vec<Value>) -> Value {
    json!({"sql": sql, "args": args, "changes": false})
}

/// The source insert is the statement whose `changes()` the app sums into "N imported".
fn counted_step(sql: String, args: Vec<Value>) -> Value {
    json!({"sql": sql, "args": args, "changes": true})
}

fn batch(family: &str, steps: Vec<Value>) -> Value {
    json!({"family": family, "steps": steps})
}

/// One import's plan: the batches to run and the counters that are not statement results.
pub struct ImportPlan {
    pub batches: Vec<Value>,
    pub type_skipped: i64,
    pub cosmetic: i64,
}

fn domain_steps(
    table: &str,
    source_table: &str,
    rule: &Value,
    source: &str,
    enabled: bool,
    now: i64,
) -> Vec<Value> {
    let identity = identity("block", Flavor::Global, rule, None, now);
    let pattern = text(rule, "pattern").unwrap_or_default();
    let raw_line = text(rule, "rawLine").unwrap_or_else(|| pattern.clone());
    let mut args = vec![
        json!(pattern),
        json!(raw_line),
        json!(now),
        json!(i32::from(flag(rule, "important").unwrap_or(false))),
        text(rule, "appScope")
            .map(Value::String)
            .unwrap_or(Value::Null),
        json!(i32::from(flag(rule, "appInverted").unwrap_or(false))),
        json!(i32::from(flag(rule, "isWildcard").unwrap_or(false))),
        text(rule, "denyallow")
            .map(Value::String)
            .unwrap_or(Value::Null),
        json!(i32::from(flag(rule, "isRegex").unwrap_or(false))),
        text(rule, "dnsType")
            .map(Value::String)
            .unwrap_or(Value::Null),
    ];
    args.extend(identity.args.iter().cloned());
    let insert = step(
        format!(
            "INSERT INTO {table} (pattern, rawLine, addedAt, enabled, groupName, important, \
             appScope, appInverted, isWildcard, denyallow, isRegex, dnsType) \
             SELECT ?, ?, ?, 1, NULL, ?, ?, ?, ?, ?, ?, ? \
             WHERE NOT EXISTS (SELECT 1 FROM {table} WHERE {})",
            identity.where_sql
        ),
        args,
    );
    // The same predicate finds the row whether it was just written or already existed.
    let mut source_args = vec![json!(source), json!(i32::from(enabled))];
    source_args.extend(identity.args.iter().cloned());
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO {source_table} (ruleId, source, enabled) \
             SELECT id, ?, ? FROM {table} WHERE {} ORDER BY id LIMIT 1",
            identity.where_sql
        ),
        source_args,
    );
    vec![insert, link]
}

fn rewrite_steps(rule: &Value, source: &str, enabled: bool, now: i64) -> Vec<Value> {
    let pattern = text(rule, "pattern").unwrap_or_default();
    let target_type = text(rule, "targetType").unwrap_or_default();
    let target_value = text(rule, "targetValue").unwrap_or_default();
    let raw_line = text(rule, "rawLine").unwrap_or_else(|| pattern.clone());
    let identity_sql = "pattern = ? AND targetType = ? AND targetValue = ?";
    let identity_args = || vec![json!(pattern), json!(target_type), json!(target_value)];
    let mut insert_args = vec![
        json!(pattern),
        json!(target_type),
        json!(target_value),
        json!(raw_line),
        json!(now),
    ];
    insert_args.extend(identity_args());
    let insert = step(
        format!(
            "INSERT INTO rewrite_rule (pattern, targetType, targetValue, rawLine, addedAt, \
             enabled) SELECT ?, ?, ?, ?, ?, 1 WHERE NOT EXISTS \
             (SELECT 1 FROM rewrite_rule WHERE {identity_sql})"
        ),
        insert_args,
    );
    let mut link_args = vec![json!(source), json!(i32::from(enabled))];
    link_args.extend(identity_args());
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO rewrite_rule_source (ruleId, source, enabled) \
             SELECT id, ?, ? FROM rewrite_rule WHERE {identity_sql} ORDER BY id LIMIT 1"
        ),
        link_args,
    );
    vec![insert, link]
}

/// URL rules go to `go_url_rule`, which has no `appScope` column, so a `$app=` rule is skipped rather
/// than stored as a global block.
fn keep_url_rule(rule: &Value) -> bool {
    match text(rule, "appScope") {
        Some(scope) => scope.trim().is_empty(),
        None => true,
    }
}

fn url_steps(rule: &Value, source: &str, enabled: bool, now: i64) -> Vec<Value> {
    let pattern = text(rule, "pattern").unwrap_or_default();
    let raw_line = text(rule, "rawLine").unwrap_or_else(|| pattern.clone());
    let kind = if flag(rule, "isAllow") == Some(true) {
        "allow"
    } else {
        "block"
    };
    let mut insert_args = vec![json!(pattern), json!(kind), json!(raw_line), json!(now)];
    insert_args.push(json!(pattern));
    insert_args.push(json!(kind));
    let insert = step(
        String::from(
            "INSERT INTO go_url_rule (pattern, kind, rawLine, addedAt, enabled) \
             SELECT ?, ?, ?, ?, 1 WHERE NOT EXISTS \
             (SELECT 1 FROM go_url_rule WHERE pattern = ? AND kind = ?)",
        ),
        insert_args,
    );
    let link = counted_step(
        String::from(
            "INSERT OR IGNORE INTO go_url_rule_source (ruleId, source, enabled) \
             SELECT id, ?, ? FROM go_url_rule WHERE pattern = ? AND kind = ? \
             ORDER BY id LIMIT 1",
        ),
        vec![
            json!(source),
            json!(i32::from(enabled)),
            json!(pattern),
            json!(kind),
        ],
    );
    vec![insert, link]
}

/// Chunks a family into batches of `chunk_size` rules; an empty family produces no batch at all.
fn push_batches(
    batches: &mut Vec<Value>,
    family: &str,
    rules: &[Value],
    chunk_size: usize,
    mut build: impl FnMut(&Value) -> Vec<Value>,
) {
    if rules.is_empty() {
        return;
    }
    let chunk_size = chunk_size.max(1);
    for chunk in rules.chunks(chunk_size) {
        let mut steps = Vec::new();
        for rule in chunk {
            steps.extend(build(rule));
        }
        batches.push(batch(family, steps));
    }
}

/// `kind` is the subscription's storage value: a `hosts` dataset has no allow/url families.
pub fn import_plan(
    parsed: &Value,
    source: &str,
    kind: &str,
    enabled: bool,
    chunk_size: usize,
    now: i64,
) -> ImportPlan {
    let domain_only = kind != "hosts";
    let mut batches = Vec::new();

    push_batches(
        &mut batches,
        "block",
        list(parsed, "blockRules"),
        chunk_size,
        |rule| {
            domain_steps(
                "block_rule",
                "block_rule_source",
                rule,
                source,
                enabled,
                now,
            )
        },
    );
    if domain_only {
        push_batches(
            &mut batches,
            "allow",
            list(parsed, "allowRules"),
            chunk_size,
            |rule| {
                domain_steps(
                    "allow_rule",
                    "allow_rule_source",
                    rule,
                    source,
                    enabled,
                    now,
                )
            },
        );
    }
    push_batches(
        &mut batches,
        "rewrite",
        list(parsed, "rewriteRules"),
        chunk_size,
        |rule| rewrite_steps(rule, source, enabled, now),
    );

    let mut type_skipped = 0;
    if domain_only {
        let url_block: Vec<Value> = list(parsed, "urlBlockRules")
            .iter()
            .filter(|rule| keep_url_rule(rule))
            .cloned()
            .collect();
        let url_allow: Vec<Value> = list(parsed, "urlAllowRules")
            .iter()
            .filter(|rule| keep_url_rule(rule))
            .cloned()
            .collect();
        push_batches(&mut batches, "urlBlock", &url_block, chunk_size, |rule| {
            url_steps(rule, source, enabled, now)
        });
        push_batches(&mut batches, "urlAllow", &url_allow, chunk_size, |rule| {
            url_steps(rule, source, enabled, now)
        });
    } else {
        type_skipped += list(parsed, "allowRules").len() as i64;
        type_skipped += list(parsed, "urlBlockRules").len() as i64;
        type_skipped += list(parsed, "urlAllowRules").len() as i64;
    }

    ImportPlan {
        batches,
        type_skipped,
        // Cosmetic rules are parsed but never stored: the engine has no injection path for them.
        cosmetic: if domain_only {
            list(parsed, "cosmeticRules").len() as i64
        } else {
            0
        },
    }
}

/// Deletes one source's rules. Only source rows go first: a rule row may be shared, so orphans are
/// swept afterwards in bounded id-range pages (one long transaction held the write lock for minutes
/// on a subscription-sized table).
pub fn remove_source_plan(source: &str) -> Value {
    let mut steps = Vec::new();
    for (_, source_table) in SOURCE_TABLES {
        steps.push(step(
            format!("DELETE FROM {source_table} WHERE source = ?"),
            vec![json!(source)],
        ));
    }
    let mut orphans = Vec::new();
    for (table, source_table) in SOURCE_TABLES {
        orphans.push(json!({
            "table": table,
            "selectSql": format!(
                "SELECT id FROM {table} WHERE NOT EXISTS \
                 (SELECT 1 FROM {source_table} s WHERE s.ruleId = {table}.id) \
                 ORDER BY id LIMIT ?"
            ),
            "selectArgs": [ORPHAN_PAGE_SIZE],
            "deletePrefix": format!("DELETE FROM {table} WHERE id IN ("),
        }));
    }
    json!({"steps": steps, "orphans": orphans})
}

/// Enables or disables every source row of one source; the shared rule row keeps its own flag.
pub fn set_source_enabled_plan(source: &str, enabled: bool) -> Value {
    let steps: Vec<Value> = SOURCE_TABLES
        .iter()
        .map(|(_, source_table)| {
            step(
                format!("UPDATE {source_table} SET enabled = ? WHERE source = ?"),
                vec![json!(i32::from(enabled)), json!(source)],
            )
        })
        .collect();
    json!({"steps": steps})
}

/// One page of a rule table with its sources joined in.
///
/// The join is part of the plan: reading the table and then its sources used to halve nothing and
/// double the peak. `beforeId` is exclusive and pages walk `id DESC`, which keeps a rule's sources
/// inside one page.
pub fn page_query(kind: &str, before_id: Option<i64>, limit: Option<i64>) -> Value {
    let (table, source_table) = crate::identity::tables(kind);
    let mut sql = format!(
        "SELECT r.*, s.source AS sourceName, s.enabled AS sourceEnabled FROM \
         (SELECT * FROM {table}"
    );
    let mut args = Vec::new();
    if let Some(before) = before_id {
        sql.push_str(" WHERE id < ?");
        args.push(json!(before));
    }
    sql.push_str(" ORDER BY id DESC");
    if let Some(limit) = limit {
        sql.push_str(" LIMIT ?");
        args.push(json!(limit));
    }
    sql.push_str(&format!(
        ") r LEFT JOIN {source_table} s ON s.ruleId = r.id ORDER BY r.id DESC"
    ));
    json!({"sql": sql, "args": args})
}

/// Table names per family, so the app never spells them itself.
pub fn tables_plan() -> Value {
    let mut families = Map::new();
    for (key, kind) in [
        ("block", "block"),
        ("allow", "allow"),
        ("rewrite", "rewrite"),
    ] {
        let (table, source_table) = crate::identity::tables(kind);
        families.insert(
            String::from(key),
            json!({"table": table, "sourceTable": source_table}),
        );
    }
    let (table, source_table) = SOURCE_TABLES[3];
    families.insert(
        String::from("url"),
        json!({"table": table, "sourceTable": source_table}),
    );
    families.insert(String::from("userSources"), json!(USER_SOURCES));
    Value::Object(families)
}

/// The counters an import reports besides the statement results.
pub fn summary(plan: &ImportPlan, parsed: &Value) -> Map<String, Value> {
    let mut summary = Map::new();
    summary.insert(String::from("typeSkipped"), json!(plan.type_skipped));
    summary.insert(String::from("cosmetic"), json!(plan.cosmetic));
    for (key, source) in [
        ("duplicate", "duplicateCount"),
        ("invalid", "invalidCount"),
        ("unsupported", "unsupportedCount"),
        ("badfiltered", "badfilteredCount"),
    ] {
        summary.insert(
            String::from(key),
            json!(integer(parsed, source).unwrap_or_default()),
        );
    }
    summary
}

#[cfg(test)]
#[path = "import/tests.rs"]
mod tests;
