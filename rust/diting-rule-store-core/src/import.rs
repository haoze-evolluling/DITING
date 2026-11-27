use serde_json::{json, Map, Value};

use crate::identity::domain_identity_sql;
use crate::probe::{flag, integer, list, text_ref};

pub const SOURCE_TABLES: [(&str, &str); 4] = [
    ("block_rule", "block_rule_source"),
    ("allow_rule", "allow_rule_source"),
    ("rewrite_rule", "rewrite_rule_source"),
    ("go_url_rule", "go_url_rule_source"),
];

pub const USER_SOURCES: [&str; 3] = ["useradd", "local_import", "local_hosts"];

pub const ORPHAN_PAGE_SIZE: i64 = 2000;

/// 单条 SQL 的多行 VALUES 行数。SQLite 默认最多 999 个绑定参数，
/// 域规则每行 10 个参数，50 行仍留有充足余量。
const BULK_ROWS: usize = 50;

const DOMAIN_TEMP: &str = "diting_import_domain";
const REWRITE_TEMP: &str = "diting_import_rewrite";
const URL_TEMP: &str = "diting_import_url";

/// 一个绑定参数。文本一律借用调用方的字符串：原生入库直接绑定到
/// rusqlite，Dart 路径在序列化时才复制，避免中间 `Value` 树。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SqlArg<'a> {
    Null,
    Int(i64),
    Text(&'a str),
}

impl SqlArg<'_> {
    pub fn to_json(&self) -> Value {
        match self {
            SqlArg::Null => Value::Null,
            SqlArg::Int(value) => json!(value),
            SqlArg::Text(value) => Value::String((*value).to_string()),
        }
    }
}

#[derive(Debug)]
pub struct PlanStep<'a> {
    pub sql: String,
    pub args: Vec<SqlArg<'a>>,
    pub changes: bool,
}

#[derive(Debug)]
pub struct PlanBatch<'a> {
    pub family: &'static str,
    pub steps: Vec<PlanStep<'a>>,
}

#[derive(Debug)]
pub struct OrphanSpec {
    pub table: &'static str,
    pub select_sql: String,
    pub select_limit: i64,
    pub delete_prefix: String,
}

/// 来源维度的计划：删除/切换某来源时执行的语句与随后要清理的孤儿页。
#[derive(Debug)]
pub struct SourcePlan<'a> {
    pub steps: Vec<PlanStep<'a>>,
    pub orphans: Vec<OrphanSpec>,
}

#[derive(Debug, Default, Clone, Copy)]
pub struct ImportCounts {
    pub type_skipped: i64,
    pub cosmetic: i64,
    pub duplicate: i64,
    pub invalid: i64,
    pub unsupported: i64,
    pub badfiltered: i64,
}

#[derive(Debug)]
pub struct ImportPlan<'a> {
    pub batches: Vec<PlanBatch<'a>>,
    pub counts: ImportCounts,
}

/// 域规则视图。`raw_line` 已按「缺省回落到 pattern」解析，
/// `denyallow` 已去掉空串，构造方无需再关心旧 JSON 的缺省语义。
pub struct DomainRule<'a> {
    pub pattern: &'a str,
    pub raw_line: &'a str,
    pub important: bool,
    pub app_scope: Option<&'a str>,
    pub app_inverted: bool,
    pub is_wildcard: bool,
    pub denyallow: Option<&'a str>,
    pub is_regex: bool,
    pub dns_type: Option<&'a str>,
    pub group: Option<&'a str>,
}

pub struct RewriteRule<'a> {
    pub pattern: &'a str,
    pub target_type: &'a str,
    pub target_value: &'a str,
    pub raw_line: &'a str,
}

pub struct UrlRule<'a> {
    pub pattern: &'a str,
    pub raw_line: &'a str,
    pub is_allow: bool,
    pub app_scope: Option<&'a str>,
}

pub struct ImportRules<'a> {
    pub block: Vec<DomainRule<'a>>,
    pub allow: Vec<DomainRule<'a>>,
    pub rewrite: Vec<RewriteRule<'a>>,
    pub url_block: Vec<UrlRule<'a>>,
    pub url_allow: Vec<UrlRule<'a>>,
    pub cosmetic: usize,
}

fn step<'a>(sql: String, args: Vec<SqlArg<'a>>) -> PlanStep<'a> {
    PlanStep {
        sql,
        args,
        changes: false,
    }
}

fn counted_step<'a>(sql: String, args: Vec<SqlArg<'a>>) -> PlanStep<'a> {
    PlanStep {
        sql,
        args,
        changes: true,
    }
}

fn optional<'a>(value: Option<&'a str>) -> SqlArg<'a> {
    value.map(SqlArg::Text).unwrap_or(SqlArg::Null)
}

fn bulk_insert_steps<'a>(
    table: &str,
    columns: &[&str],
    rows: Vec<Vec<SqlArg<'a>>>,
) -> Vec<PlanStep<'a>> {
    let mut steps = Vec::new();
    let width = columns.len();
    for chunk in rows.chunks(BULK_ROWS) {
        let mut placeholders = Vec::with_capacity(chunk.len());
        for _ in 0..chunk.len() {
            placeholders.push(format!("({})", vec!["?"; width].join(", ")));
        }
        let insert_args = chunk.iter().flatten().copied().collect();
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

fn create_temp_step(table: &str, columns: &str) -> PlanStep<'static> {
    step(
        format!("CREATE TEMP TABLE IF NOT EXISTS {table} ({columns})"),
        Vec::new(),
    )
}

fn clear_temp_step(table: &str) -> PlanStep<'static> {
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
fn domain_batch_steps<'a>(
    table: &str,
    source_table: &str,
    rules: &[DomainRule<'a>],
    source: &'a str,
    enabled: bool,
    now: i64,
) -> Vec<PlanStep<'a>> {
    let rows: Vec<Vec<SqlArg<'a>>> = rules
        .iter()
        .map(|rule| {
            vec![
                SqlArg::Text(rule.pattern),
                SqlArg::Text(rule.raw_line),
                SqlArg::Int(i64::from(rule.important)),
                optional(rule.app_scope),
                SqlArg::Int(i64::from(rule.app_inverted)),
                SqlArg::Int(i64::from(rule.is_wildcard)),
                optional(rule.denyallow),
                SqlArg::Int(i64::from(rule.is_regex)),
                optional(rule.dns_type),
                optional(rule.group),
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
        vec![SqlArg::Int(now)],
    );
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO {source_table} (ruleId, source, enabled) \
             SELECT r.id, ?, ? FROM {DOMAIN_TEMP} t JOIN {table} r ON {identity_sql}"
        ),
        vec![SqlArg::Text(source), SqlArg::Int(i64::from(enabled))],
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

fn rewrite_batch_steps<'a>(
    rules: &[RewriteRule<'a>],
    source: &'a str,
    enabled: bool,
    now: i64,
) -> Vec<PlanStep<'a>> {
    let rows: Vec<Vec<SqlArg<'a>>> = rules
        .iter()
        .map(|rule| {
            vec![
                SqlArg::Text(rule.pattern),
                SqlArg::Text(rule.target_type),
                SqlArg::Text(rule.target_value),
                SqlArg::Text(rule.raw_line),
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
        vec![SqlArg::Int(now)],
    );
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO rewrite_rule_source (ruleId, source, enabled) \
             SELECT r.id, ?, ? FROM {REWRITE_TEMP} t JOIN rewrite_rule r ON {identity_sql}"
        ),
        vec![SqlArg::Text(source), SqlArg::Int(i64::from(enabled))],
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

fn keep_url_rule(rule: &UrlRule<'_>) -> bool {
    match rule.app_scope {
        Some(scope) => scope.trim().is_empty(),
        None => true,
    }
}

fn url_batch_steps<'a>(
    rules: &[UrlRule<'a>],
    source: &'a str,
    enabled: bool,
    now: i64,
) -> Vec<PlanStep<'a>> {
    let rows: Vec<Vec<SqlArg<'a>>> = rules
        .iter()
        .map(|rule| {
            let kind = if rule.is_allow { "allow" } else { "block" };
            vec![
                SqlArg::Text(rule.pattern),
                SqlArg::Text(kind),
                SqlArg::Text(rule.raw_line),
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
        vec![SqlArg::Int(now)],
    );
    let link = counted_step(
        format!(
            "INSERT OR IGNORE INTO go_url_rule_source (ruleId, source, enabled) \
             SELECT r.id, ?, ? FROM {URL_TEMP} t JOIN go_url_rule r ON {identity_sql}"
        ),
        vec![SqlArg::Text(source), SqlArg::Int(i64::from(enabled))],
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

fn push_batches<'a, T>(
    batches: &mut Vec<PlanBatch<'a>>,
    family: &'static str,
    rules: &[T],
    chunk_size: usize,
    build: impl Fn(&[T]) -> Vec<PlanStep<'a>>,
) {
    if rules.is_empty() {
        return;
    }
    let chunk_size = chunk_size.max(1);
    for chunk in rules.chunks(chunk_size) {
        batches.push(PlanBatch {
            family,
            steps: build(chunk),
        });
    }
}

/// 生成导入计划。`counts` 只带入解析阶段已经算好的计数，
/// `type_skipped` 与 `cosmetic` 由收录类型决定。
pub fn build_import_plan<'a>(
    mut rules: ImportRules<'a>,
    mut counts: ImportCounts,
    source: &'a str,
    kind: &str,
    enabled: bool,
    chunk_size: usize,
    now: i64,
) -> ImportPlan<'a> {
    let domain_only = kind != "hosts";
    let mut batches = Vec::new();

    let url_block = std::mem::take(&mut rules.url_block);
    let url_allow = std::mem::take(&mut rules.url_allow);

    push_batches(&mut batches, "block", &rules.block, chunk_size, |rules| {
        domain_batch_steps(
            "block_rule",
            "block_rule_source",
            rules,
            source,
            enabled,
            now,
        )
    });
    if domain_only {
        push_batches(&mut batches, "allow", &rules.allow, chunk_size, |rules| {
            domain_batch_steps(
                "allow_rule",
                "allow_rule_source",
                rules,
                source,
                enabled,
                now,
            )
        });
    }
    push_batches(
        &mut batches,
        "rewrite",
        &rules.rewrite,
        chunk_size,
        |rules| rewrite_batch_steps(rules, source, enabled, now),
    );

    if domain_only {
        let url_block: Vec<UrlRule<'a>> = url_block.into_iter().filter(keep_url_rule).collect();
        let url_allow: Vec<UrlRule<'a>> = url_allow.into_iter().filter(keep_url_rule).collect();
        push_batches(&mut batches, "urlBlock", &url_block, chunk_size, |rules| {
            url_batch_steps(rules, source, enabled, now)
        });
        push_batches(&mut batches, "urlAllow", &url_allow, chunk_size, |rules| {
            url_batch_steps(rules, source, enabled, now)
        });
        counts.type_skipped = 0;
        counts.cosmetic = rules.cosmetic as i64;
    } else {
        counts.type_skipped = (rules.allow.len() + url_block.len() + url_allow.len()) as i64;
        counts.cosmetic = 0;
    }

    ImportPlan { batches, counts }
}

fn domain_view(rule: &Value) -> DomainRule<'_> {
    let pattern = text_ref(rule, "pattern").unwrap_or_default();
    DomainRule {
        pattern,
        raw_line: text_ref(rule, "rawLine").unwrap_or(pattern),
        important: flag(rule, "important").unwrap_or(false),
        app_scope: text_ref(rule, "appScope"),
        app_inverted: flag(rule, "appInverted").unwrap_or(false),
        is_wildcard: flag(rule, "isWildcard").unwrap_or(false),
        denyallow: text_ref(rule, "denyallow").filter(|value| !value.is_empty()),
        is_regex: flag(rule, "isRegex").unwrap_or(false),
        dns_type: text_ref(rule, "dnsType"),
        group: text_ref(rule, "group"),
    }
}

fn rewrite_view(rule: &Value) -> RewriteRule<'_> {
    let pattern = text_ref(rule, "pattern").unwrap_or_default();
    RewriteRule {
        pattern,
        target_type: text_ref(rule, "targetType").unwrap_or_default(),
        target_value: text_ref(rule, "targetValue").unwrap_or_default(),
        raw_line: text_ref(rule, "rawLine").unwrap_or(pattern),
    }
}

fn url_view(rule: &Value) -> UrlRule<'_> {
    let pattern = text_ref(rule, "pattern").unwrap_or_default();
    UrlRule {
        pattern,
        raw_line: text_ref(rule, "rawLine").unwrap_or(pattern),
        is_allow: flag(rule, "isAllow").unwrap_or(false),
        app_scope: text_ref(rule, "appScope"),
    }
}

/// JSON 边界版本：把 Dart 传来的规则对象转成借用视图后交给强类型计划。
pub fn import_plan<'a>(
    parsed: &'a Value,
    source: &'a str,
    kind: &str,
    enabled: bool,
    chunk_size: usize,
    now: i64,
) -> ImportPlan<'a> {
    let rules = ImportRules {
        block: list(parsed, "blockRules").iter().map(domain_view).collect(),
        allow: list(parsed, "allowRules").iter().map(domain_view).collect(),
        rewrite: list(parsed, "rewriteRules")
            .iter()
            .map(rewrite_view)
            .collect(),
        url_block: list(parsed, "urlBlockRules").iter().map(url_view).collect(),
        url_allow: list(parsed, "urlAllowRules").iter().map(url_view).collect(),
        cosmetic: list(parsed, "cosmeticRules").len(),
    };
    let counts = ImportCounts {
        duplicate: integer(parsed, "duplicateCount").unwrap_or_default(),
        invalid: integer(parsed, "invalidCount").unwrap_or_default(),
        unsupported: integer(parsed, "unsupportedCount").unwrap_or_default(),
        badfiltered: integer(parsed, "badfilteredCount").unwrap_or_default(),
        ..ImportCounts::default()
    };
    build_import_plan(rules, counts, source, kind, enabled, chunk_size, now)
}

fn orphan_specs() -> Vec<OrphanSpec> {
    let mut orphans = Vec::new();
    for (table, source_table) in SOURCE_TABLES {
        orphans.push(OrphanSpec {
            table,
            select_sql: format!(
                "SELECT id FROM {table} WHERE NOT EXISTS \
                 (SELECT 1 FROM {source_table} s WHERE s.ruleId = {table}.id) \
                 ORDER BY id LIMIT ?"
            ),
            select_limit: ORPHAN_PAGE_SIZE,
            delete_prefix: format!("DELETE FROM {table} WHERE id IN ("),
        });
    }
    orphans
}

pub fn remove_source_plan<'a>(source: &'a str) -> SourcePlan<'a> {
    let steps = SOURCE_TABLES
        .iter()
        .map(|(_, source_table)| {
            step(
                format!("DELETE FROM {source_table} WHERE source = ?"),
                vec![SqlArg::Text(source)],
            )
        })
        .collect();
    SourcePlan {
        steps,
        orphans: orphan_specs(),
    }
}

/// 暂存导入完成后的原子切换：先用暂存来源覆盖正式来源，
/// 再删除暂存行；同一事务内完成，失败时旧规则原样保留。
pub fn commit_source_plan<'a>(staging: &'a str, source: &'a str, enabled: bool) -> SourcePlan<'a> {
    let mut steps = Vec::new();
    for (_, source_table) in SOURCE_TABLES {
        steps.push(step(
            format!("DELETE FROM {source_table} WHERE source = ?"),
            vec![SqlArg::Text(source)],
        ));
        // 启用状态以提交时的订阅状态为准，避免导入期间用户切换开关后
        // 被暂存行里的旧状态覆盖。
        steps.push(step(
            format!(
                "INSERT OR IGNORE INTO {source_table} (ruleId, source, enabled) \
                 SELECT ruleId, ?, ? FROM {source_table} WHERE source = ?"
            ),
            vec![
                SqlArg::Text(source),
                SqlArg::Int(i64::from(enabled)),
                SqlArg::Text(staging),
            ],
        ));
        steps.push(step(
            format!("DELETE FROM {source_table} WHERE source = ?"),
            vec![SqlArg::Text(staging)],
        ));
    }
    SourcePlan {
        steps,
        orphans: orphan_specs(),
    }
}

pub fn set_source_enabled_plan<'a>(source: &'a str, enabled: bool) -> SourcePlan<'a> {
    let steps = SOURCE_TABLES
        .iter()
        .map(|(_, source_table)| {
            step(
                format!("UPDATE {source_table} SET enabled = ? WHERE source = ?"),
                vec![SqlArg::Int(i64::from(enabled)), SqlArg::Text(source)],
            )
        })
        .collect();
    SourcePlan {
        steps,
        orphans: Vec::new(),
    }
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

pub fn summary(plan: &ImportPlan<'_>) -> Map<String, Value> {
    let mut summary = Map::new();
    summary.insert(String::from("typeSkipped"), json!(plan.counts.type_skipped));
    summary.insert(String::from("cosmetic"), json!(plan.counts.cosmetic));
    summary.insert(String::from("duplicate"), json!(plan.counts.duplicate));
    summary.insert(String::from("invalid"), json!(plan.counts.invalid));
    summary.insert(String::from("unsupported"), json!(plan.counts.unsupported));
    summary.insert(String::from("badfiltered"), json!(plan.counts.badfiltered));
    summary
}

/// Dart 侧的 JSON 计划输出。原生入库直接使用强类型计划，不经过这里。
pub fn steps_json(steps: &[PlanStep<'_>]) -> Vec<Value> {
    steps
        .iter()
        .map(|step| {
            json!({
                "sql": step.sql,
                "args": step.args.iter().map(SqlArg::to_json).collect::<Vec<Value>>(),
                "changes": step.changes,
            })
        })
        .collect()
}

pub fn batches_json(batches: &[PlanBatch<'_>]) -> Vec<Value> {
    batches
        .iter()
        .map(|batch| {
            json!({
                "family": batch.family,
                "steps": steps_json(&batch.steps),
            })
        })
        .collect()
}

pub fn plan_json(plan: &SourcePlan<'_>) -> Value {
    json!({
        "steps": steps_json(&plan.steps),
        "orphans": plan
            .orphans
            .iter()
            .map(|orphan| json!({
                "table": orphan.table,
                "selectSql": orphan.select_sql,
                "selectArgs": [orphan.select_limit],
                "deletePrefix": orphan.delete_prefix,
            }))
            .collect::<Vec<Value>>(),
    })
}

#[cfg(test)]
#[path = "import/tests.rs"]
mod tests;
