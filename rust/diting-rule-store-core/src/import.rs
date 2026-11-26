use serde_json::{json, Map, Value};

use crate::identity::{domain_identity_sql, non_empty};
use crate::probe::{flag, integer, list, text};

pub const SOURCE_TABLES: [(&str, &str); 4] = [
    ("block_rule", "block_rule_source"),
    ("allow_rule", "allow_rule_source"),
    ("rewrite_rule", "rewrite_rule_source"),
    ("go_url_rule", "go_url_rule_source"),
];

pub const USER_SOURCES: [&str; 3] = ["useradd", "local_import", "local_hosts"];

pub const ORPHAN_PAGE_SIZE: i64 = 2000;

fn step(sql: String, args: Vec<Value>) -> Value {
    json!({"sql": sql, "args": args, "changes": false})
}

fn counted_step(sql: String, args: Vec<Value>) -> Value {
    json!({"sql": sql, "args": args, "changes": true})
}

fn batch(family: &str, steps: Vec<Value>) -> Value {
    json!({"family": family, "steps": steps})
}

pub struct ImportPlan {
    pub batches: Vec<Value>,
    pub type_skipped: i64,
    pub cosmetic: i64,
}

/// 单条 SQL 的多行 VALUES 行数。SQLite 默认最多 999 个绑定参数，
/// 域规则每行 10 个参数，50 行仍留有充足余量。
const BULK_ROWS: usize = 50;

const DOMAIN_TEMP: &str = "diting_import_domain";
const REWRITE_TEMP: &str = "diting_import_rewrite";
const URL_TEMP: &str = "diting_import_url";

fn optional(value: Option<String>) -> Value {
    value.map(Value::String).unwrap_or(Value::Null)
}

fn bulk_insert_steps(table: &str, columns: &[&str], rows: Vec<Vec<Value>>) -> Vec<Value> {
    let mut steps = Vec::new();
    let width = columns.len();
    for chunk in rows.chunks(BULK_ROWS) {
        let mut placeholders = Vec::with_capacity(chunk.len());
        for _ in 0..chunk.len() {
            placeholders.push(format!("({})", vec!["?"; width].join(", ")));
        }
        let insert_args = chunk.iter().flatten().cloned().collect();
        steps.push(step(
            format!(
                "INSERT INTO {table} ({}) VALUES {}",
                columns.join(", "),
                placeholders.join(", ")
            ),
            insert_args,
        ));
    }
    steps
}

fn create_temp_step(table: &str, columns: &str) -> Value {
    step(
        format!("CREATE TEMP TABLE IF NOT EXISTS {table} ({columns})"),
        Vec::new(),
    )
}

fn clear_temp_step(table: &str) -> Value {
    step(format!("DELETE FROM {table}"), Vec::new())
}

fn domain_temp_columns() -> [&'static str; 10] {
    [
        "pattern",
        "rawLine",
        "important",
        "appScope",
        "appInverted",
        "isWildcard",
        "denyallow",
        "isRegex",
        "dnsType",
        "groupName",
    ]
}

fn domain_temp_sql() -> &'static str {
    "pattern TEXT, rawLine TEXT, important INTEGER, appScope TEXT, appInverted INTEGER, \
     isWildcard INTEGER, denyallow TEXT, isRegex INTEGER, dnsType TEXT, groupName TEXT"
}

/// 把一批域名规则先灌入临时表，再用两条集合语句完成去重与来源关联。
/// 相比逐条 INSERT，SQL 语句数从 3N 降到 N/50+4。
fn domain_batch_steps(
    table: &str,
    source_table: &str,
    rules: &[Value],
    source: &str,
    enabled: bool,
    now: i64,
) -> Vec<Value> {
    let rows: Vec<Vec<Value>> = rules
        .iter()
        .map(|rule| {
            let pattern = text(rule, "pattern").unwrap_or_default();
            let raw_line = text(rule, "rawLine").unwrap_or_else(|| pattern.clone());
            vec![
                json!(pattern),
                json!(raw_line),
                json!(i32::from(flag(rule, "important").unwrap_or(false))),
                optional(text(rule, "appScope")),
                json!(i32::from(flag(rule, "appInverted").unwrap_or(false))),
                json!(i32::from(flag(rule, "isWildcard").unwrap_or(false))),
                optional(non_empty(text(rule, "denyallow"))),
                json!(i32::from(flag(rule, "isRegex").unwrap_or(false))),
                optional(text(rule, "dnsType")),
                optional(text(rule, "group")),
            ]
        })
        .collect();

    let identity_sql = domain_identity_sql("r", "t");
    let insert = step(
        format!(
            "INSERT INTO {table} (pattern, rawLine, addedAt, enabled, groupName, important, \
             appScope, appInverted, isWildcard, denyallow, isRegex, dnsType) \
             SELECT t.pattern, t.rawLine, ?, 1, t.groupName, t.important, t.appScope, \
             t.appInverted, t.isWildcard, t.denyallow, t.isRegex, t.dnsType \
             FROM {DOMAIN_TEMP} t \
             WHERE NOT EXISTS (SELECT 1 FROM {table} r WHERE {identity_sql})"
        ),
        vec![json!(now)],
    );
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO {source_table} (ruleId, source, enabled) \
             SELECT r.id, ?, ? FROM {DOMAIN_TEMP} t JOIN {table} r ON {identity_sql}"
        ),
        vec![json!(source), json!(i32::from(enabled))],
    );

    let mut steps = vec![
        create_temp_step(DOMAIN_TEMP, domain_temp_sql()),
        step(format!("DELETE FROM {DOMAIN_TEMP}"), Vec::new()),
    ];
    steps.extend(bulk_insert_steps(DOMAIN_TEMP, &domain_temp_columns(), rows));
    steps.push(insert);
    steps.push(link);
    steps.push(clear_temp_step(DOMAIN_TEMP));
    steps
}

fn rewrite_batch_steps(rules: &[Value], source: &str, enabled: bool, now: i64) -> Vec<Value> {
    let rows: Vec<Vec<Value>> = rules
        .iter()
        .map(|rule| {
            let pattern = text(rule, "pattern").unwrap_or_default();
            vec![
                json!(pattern.clone()),
                json!(text(rule, "targetType").unwrap_or_default()),
                json!(text(rule, "targetValue").unwrap_or_default()),
                json!(text(rule, "rawLine").unwrap_or(pattern)),
            ]
        })
        .collect();
    let identity_sql = "r.pattern = t.pattern AND r.targetType = t.targetType \
         AND r.targetValue = t.targetValue";
    let insert = step(
        format!(
            "INSERT INTO rewrite_rule (pattern, targetType, targetValue, rawLine, addedAt, \
             enabled) SELECT t.pattern, t.targetType, t.targetValue, t.rawLine, ?, 1 \
             FROM {REWRITE_TEMP} t \
             WHERE NOT EXISTS (SELECT 1 FROM rewrite_rule r WHERE {identity_sql})"
        ),
        vec![json!(now)],
    );
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO rewrite_rule_source (ruleId, source, enabled) \
             SELECT r.id, ?, ? FROM {REWRITE_TEMP} t JOIN rewrite_rule r ON {identity_sql}"
        ),
        vec![json!(source), json!(i32::from(enabled))],
    );
    let mut steps = vec![
        create_temp_step(
            REWRITE_TEMP,
            "pattern TEXT, targetType TEXT, targetValue TEXT, rawLine TEXT",
        ),
        step(format!("DELETE FROM {REWRITE_TEMP}"), Vec::new()),
    ];
    steps.extend(bulk_insert_steps(
        REWRITE_TEMP,
        &["pattern", "targetType", "targetValue", "rawLine"],
        rows,
    ));
    steps.push(insert);
    steps.push(link);
    steps.push(clear_temp_step(REWRITE_TEMP));
    steps
}

fn keep_url_rule(rule: &Value) -> bool {
    match text(rule, "appScope") {
        Some(scope) => scope.trim().is_empty(),
        None => true,
    }
}

fn url_batch_steps(rules: &[Value], source: &str, enabled: bool, now: i64) -> Vec<Value> {
    let rows: Vec<Vec<Value>> = rules
        .iter()
        .map(|rule| {
            let pattern = text(rule, "pattern").unwrap_or_default();
            let kind = if flag(rule, "isAllow") == Some(true) {
                "allow"
            } else {
                "block"
            };
            vec![
                json!(pattern.clone()),
                json!(kind),
                json!(text(rule, "rawLine").unwrap_or(pattern)),
            ]
        })
        .collect();
    let identity_sql = "r.pattern = t.pattern AND r.kind = t.kind";
    let insert = step(
        format!(
            "INSERT INTO go_url_rule (pattern, kind, rawLine, addedAt, enabled) \
             SELECT t.pattern, t.kind, t.rawLine, ?, 1 FROM {URL_TEMP} t \
             WHERE NOT EXISTS (SELECT 1 FROM go_url_rule r WHERE {identity_sql})"
        ),
        vec![json!(now)],
    );
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO go_url_rule_source (ruleId, source, enabled) \
             SELECT r.id, ?, ? FROM {URL_TEMP} t JOIN go_url_rule r ON {identity_sql}"
        ),
        vec![json!(source), json!(i32::from(enabled))],
    );
    let mut steps = vec![
        create_temp_step(URL_TEMP, "pattern TEXT, kind TEXT, rawLine TEXT"),
        step(format!("DELETE FROM {URL_TEMP}"), Vec::new()),
    ];
    steps.extend(bulk_insert_steps(
        URL_TEMP,
        &["pattern", "kind", "rawLine"],
        rows,
    ));
    steps.push(insert);
    steps.push(link);
    steps.push(clear_temp_step(URL_TEMP));
    steps
}

fn push_batches(
    batches: &mut Vec<Value>,
    family: &str,
    rules: &[Value],
    chunk_size: usize,
    build: impl Fn(&[Value]) -> Vec<Value>,
) {
    if rules.is_empty() {
        return;
    }
    let chunk_size = chunk_size.max(1);
    for chunk in rules.chunks(chunk_size) {
        batches.push(batch(family, build(chunk)));
    }
}

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
        |rules| {
            domain_batch_steps(
                "block_rule",
                "block_rule_source",
                rules,
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
            |rules| {
                domain_batch_steps(
                    "allow_rule",
                    "allow_rule_source",
                    rules,
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
        |rules| rewrite_batch_steps(rules, source, enabled, now),
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
        push_batches(&mut batches, "urlBlock", &url_block, chunk_size, |rules| {
            url_batch_steps(rules, source, enabled, now)
        });
        push_batches(&mut batches, "urlAllow", &url_allow, chunk_size, |rules| {
            url_batch_steps(rules, source, enabled, now)
        });
    } else {
        type_skipped += list(parsed, "allowRules").len() as i64;
        type_skipped += list(parsed, "urlBlockRules").len() as i64;
        type_skipped += list(parsed, "urlAllowRules").len() as i64;
    }

    ImportPlan {
        batches,
        type_skipped,
        cosmetic: if domain_only {
            list(parsed, "cosmeticRules").len() as i64
        } else {
            0
        },
    }
}

fn orphan_specs() -> Vec<Value> {
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
    orphans
}

pub fn remove_source_plan(source: &str) -> Value {
    let steps: Vec<Value> = SOURCE_TABLES
        .iter()
        .map(|(_, source_table)| {
            step(
                format!("DELETE FROM {source_table} WHERE source = ?"),
                vec![json!(source)],
            )
        })
        .collect();
    json!({"steps": steps, "orphans": orphan_specs()})
}

/// 暂存导入完成后的原子切换：先用暂存来源覆盖正式来源，
/// 再删除暂存行；同一事务内完成，失败时旧规则原样保留。
pub fn commit_source_plan(staging: &str, source: &str, enabled: bool) -> Value {
    let mut steps = Vec::new();
    for (_, source_table) in SOURCE_TABLES {
        steps.push(step(
            format!("DELETE FROM {source_table} WHERE source = ?"),
            vec![json!(source)],
        ));
        // 启用状态以提交时的订阅状态为准，避免导入期间用户切换开关后
        // 被暂存行里的旧状态覆盖。
        steps.push(step(
            format!(
                "INSERT OR IGNORE INTO {source_table} (ruleId, source, enabled) \
                 SELECT ruleId, ?, ? FROM {source_table} WHERE source = ?"
            ),
            vec![json!(source), json!(i32::from(enabled)), json!(staging)],
        ));
        steps.push(step(
            format!("DELETE FROM {source_table} WHERE source = ?"),
            vec![json!(staging)],
        ));
    }
    json!({"steps": steps, "orphans": orphan_specs()})
}

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
