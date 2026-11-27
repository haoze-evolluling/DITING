//! 订阅原文 → 规则库的原地导入。
//!
//! 解析、去重与 SQL 生成沿用 `diting-rule-store-core` 的强类型计划，计划不再经过
//! JSON/FFI/sqflite 通道，而是由本模块在同一个事务里直接执行：
//!
//! * 规则对象直接进入 SQL 绑定参数，没有中间 `serde_json::Value` 树；
//! * 内容未变化时只做一次纯解析核对哈希，不打开写事务；
//! * 所有写入在一个事务内完成，失败或被删除时整体回滚，不留半套规则；
//! * 提交前重新读取订阅的启用状态，避免导入期间用户切换开关被旧值覆盖。

use std::time::Duration;

use diting_rule_core::models::{ParsedRewriteRule, ParsedUrlRule};
use diting_rule_core::{CategorizedRules, ParsedRule, StreamParse};
use diting_rule_store_core::import::{
    build_import_plan, commit_source_plan, remove_source_plan, DomainRule, ImportCounts,
    ImportRules, OrphanSpec, PlanStep, RewriteRule, SqlArg, UrlRule,
};
use rusqlite::types::{ToSqlOutput, Value as SqlValue, ValueRef};
use rusqlite::{params_from_iter, Connection, OpenFlags, ToSql, Transaction};
use serde_json::{json, Map, Value};

use crate::probe::{flag, integer, text};

/// 与 Dart `ruleSetHashSeed` / `ruleSetHashPrime` 一致（FNV-1a，32 位，
/// 按 UTF-16 code unit 计算，非 BMP 字符会拆成代理对）。
const HASH_SEED: u32 = 0x811c9dc5;
const HASH_PRIME: u32 = 0x01000193;

const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

pub fn run(request: &Value) -> Result<Value, String> {
    let db_path = text(request, "dbPath").ok_or_else(|| "missing dbPath".to_string())?;
    let document = text(request, "text").ok_or_else(|| "missing text".to_string())?;
    let source = text(request, "source").ok_or_else(|| "missing source".to_string())?;
    let staging = text(request, "staging").ok_or_else(|| "missing staging".to_string())?;
    let kind = text(request, "kind").unwrap_or_else(|| String::from("domain"));
    let enabled = flag(request, "enabled").unwrap_or(true);
    let subscription_id = integer(request, "subscriptionId").unwrap_or_default();
    let chunk_lines = integer(request, "chunkLines").unwrap_or(2048).max(1) as usize;
    let chunk_size = integer(request, "chunkSize").unwrap_or(1000).max(1) as usize;
    let now = integer(request, "nowMs").unwrap_or_default();
    let known_hash = text(request, "knownHash");
    let max_version = integer(request, "maxVersionRules").unwrap_or(60000).max(0) as usize;

    // 内容未变化时不做任何写库动作：先用一次纯解析核对哈希，
    // 避免「服务器返回 200 但正文相同」的订阅白白重写整张表。
    if let Some(known) = known_hash.as_deref() {
        if document_hash(&document, chunk_lines) == known {
            return Ok(json!({
                "unchanged": true,
                "deleted": false,
                "hash": known,
                "counts": {},
                "parsed": {},
                "versionRules": [],
                "versionSkipped": false,
            }));
        }
    }

    let mut connection = Connection::open_with_flags(&db_path, OpenFlags::SQLITE_OPEN_READ_WRITE)
        .map_err(|error| error.to_string())?;
    connection
        .busy_timeout(BUSY_TIMEOUT)
        .map_err(|error| error.to_string())?;
    connection
        .pragma_update(None, "foreign_keys", "ON")
        .map_err(|error| error.to_string())?;
    let transaction = connection
        .transaction()
        .map_err(|error| error.to_string())?;

    // 上次导入若中途退出，暂存来源可能仍有残留；先清掉再重新写入。
    let cleanup = remove_source_plan(&staging);
    execute_steps(&transaction, &cleanup.steps)?;
    sweep_orphans(&transaction, &cleanup.orphans)?;

    let context = ImportContext {
        staging: &staging,
        kind: &kind,
        enabled,
        chunk_size,
        now,
    };
    let mut import = ImportRun::new(max_version);
    let mut stream = StreamParse::new(document, chunk_lines);
    while let Some(chunk) = stream.next_rules() {
        import.consume(&transaction, &chunk, &context)?;
    }

    let hash = import.hash();

    // 订阅可能在导入期间被删除或切换了开关，以提交时的状态为准。
    let current: Option<i64> = transaction
        .query_row(
            "SELECT enabled FROM subscription WHERE id = ?1",
            [subscription_id],
            |row| row.get(0),
        )
        .ok();
    let Some(current_enabled) = current else {
        drop(transaction);
        return Ok(json!({
            "unchanged": false,
            "deleted": true,
            "hash": hash,
        }));
    };

    let commit = commit_source_plan(&staging, &source, current_enabled != 0);
    execute_steps(&transaction, &commit.steps)?;
    sweep_orphans(&transaction, &commit.orphans)?;
    transaction.commit().map_err(|error| error.to_string())?;

    Ok(json!({
        "unchanged": false,
        "deleted": false,
        "hash": hash,
        "counts": import.counts,
        "parsed": import.parsed,
        "versionRules": import.version_rules,
        "versionSkipped": import.version_skipped,
    }))
}

struct ImportContext<'a> {
    staging: &'a str,
    kind: &'a str,
    enabled: bool,
    chunk_size: usize,
    now: i64,
}

struct ImportRun {
    hash_state: u32,
    counts: Map<String, Value>,
    parsed: Map<String, Value>,
    version_rules: Vec<String>,
    version_skipped: bool,
    max_version: usize,
}

impl ImportRun {
    fn new(max_version: usize) -> Self {
        Self {
            hash_state: HASH_SEED,
            counts: Map::new(),
            parsed: Map::new(),
            version_rules: Vec::new(),
            version_skipped: false,
            max_version,
        }
    }

    fn hash(&self) -> String {
        format!("{:08x}", self.hash_state)
    }

    fn consume(
        &mut self,
        transaction: &Transaction,
        chunk: &CategorizedRules,
        context: &ImportContext<'_>,
    ) -> Result<(), String> {
        let lines = canonical_lines(chunk);
        self.hash_state = hash_lines(self.hash_state, &lines);
        self.collect_version(&lines);

        let plan = build_import_plan(
            chunk_rules(chunk),
            chunk_counts(chunk),
            context.staging,
            context.kind,
            context.enabled,
            context.chunk_size,
            context.now,
        );
        for batch in &plan.batches {
            let mut total = 0i64;
            for step in &batch.steps {
                if let Some(changed) = execute_step(transaction, step)? {
                    total += changed;
                }
            }
            add_count(&mut self.counts, batch.family, total);
        }
        self.add_parsed(&plan.counts);
        Ok(())
    }

    fn add_parsed(&mut self, counts: &ImportCounts) {
        for (key, value) in [
            ("typeSkipped", counts.type_skipped),
            ("cosmetic", counts.cosmetic),
            ("duplicate", counts.duplicate),
            ("invalid", counts.invalid),
            ("unsupported", counts.unsupported),
            ("badfiltered", counts.badfiltered),
        ] {
            add_count(&mut self.parsed, key, value);
        }
    }

    fn collect_version(&mut self, lines: &[String]) {
        if self.version_skipped {
            return;
        }
        if self.version_rules.len() + lines.len() <= self.max_version {
            self.version_rules.extend(lines.iter().cloned());
        } else {
            self.version_skipped = true;
            self.version_rules.clear();
        }
    }
}

fn add_count(counts: &mut Map<String, Value>, key: &str, value: i64) {
    let entry = counts.entry(key.to_string()).or_insert_with(|| json!(0));
    *entry = json!(entry.as_i64().unwrap_or(0) + value);
}

/// 只做解析与哈希，不生成任何 SQL；用于在写库前判断内容是否变化。
fn document_hash(text: &str, chunk_lines: usize) -> String {
    let mut stream = StreamParse::new(text.to_string(), chunk_lines);
    let mut state = HASH_SEED;
    while let Some(chunk) = stream.next_rules() {
        state = hash_lines(state, &canonical_lines(&chunk));
    }
    format!("{state:08x}")
}

fn hash_lines(mut state: u32, lines: &[String]) -> u32 {
    for line in lines {
        for unit in line.encode_utf16() {
            state ^= u32::from(unit);
            state = state.wrapping_mul(HASH_PRIME);
        }
        state ^= 0x0a;
        state = state.wrapping_mul(HASH_PRIME);
    }
    state
}

/// 与 Dart `canonicalRules` 相同的顺序：屏蔽、允许、重写、URL 屏蔽、URL 允许。
fn canonical_lines(chunk: &CategorizedRules) -> Vec<String> {
    let mut lines = Vec::new();
    for rule in &chunk.block_rules {
        lines.push(rule.raw_line.clone());
    }
    for rule in &chunk.allow_rules {
        lines.push(rule.raw_line.clone());
    }
    for rule in &chunk.rewrite_rules {
        lines.push(rule.raw_line.clone());
    }
    for rule in &chunk.url_block_rules {
        lines.push(rule.raw_line.clone());
    }
    for rule in &chunk.url_allow_rules {
        lines.push(rule.raw_line.clone());
    }
    lines
}

fn chunk_rules(chunk: &CategorizedRules) -> ImportRules<'_> {
    ImportRules {
        block: chunk.block_rules.iter().map(domain_rule).collect(),
        allow: chunk.allow_rules.iter().map(domain_rule).collect(),
        rewrite: chunk.rewrite_rules.iter().map(rewrite_rule).collect(),
        url_block: chunk.url_block_rules.iter().map(url_rule).collect(),
        url_allow: chunk.url_allow_rules.iter().map(url_rule).collect(),
        cosmetic: chunk.cosmetic_rules.len(),
    }
}

fn chunk_counts(chunk: &CategorizedRules) -> ImportCounts {
    ImportCounts {
        duplicate: i64::from(chunk.duplicate_count),
        invalid: i64::from(chunk.invalid_count),
        unsupported: i64::from(chunk.unsupported_count),
        badfiltered: i64::from(chunk.badfiltered_count),
        ..ImportCounts::default()
    }
}

fn domain_rule(rule: &ParsedRule) -> DomainRule<'_> {
    DomainRule {
        pattern: &rule.pattern,
        raw_line: &rule.raw_line,
        important: rule.important,
        app_scope: rule.app_scope.as_deref(),
        app_inverted: rule.app_inverted,
        is_wildcard: rule.is_wildcard,
        denyallow: rule.denyallow.as_deref().filter(|value| !value.is_empty()),
        is_regex: rule.is_regex,
        dns_type: rule.dns_type.as_deref(),
        group: None,
    }
}

fn rewrite_rule(rule: &ParsedRewriteRule) -> RewriteRule<'_> {
    RewriteRule {
        pattern: &rule.pattern,
        target_type: &rule.target_type,
        target_value: &rule.target_value,
        raw_line: &rule.raw_line,
    }
}

fn url_rule(rule: &ParsedUrlRule) -> UrlRule<'_> {
    UrlRule {
        pattern: &rule.pattern,
        raw_line: &rule.raw_line,
        is_allow: rule.is_allow,
        app_scope: rule.app_scope.as_deref(),
    }
}

fn execute_steps(transaction: &Transaction, steps: &[PlanStep<'_>]) -> Result<(), String> {
    for step in steps {
        execute_step(transaction, step)?;
    }
    Ok(())
}

fn execute_step(transaction: &Transaction, step: &PlanStep<'_>) -> Result<Option<i64>, String> {
    let mut statement = transaction
        .prepare(&step.sql)
        .map_err(|error| format!("{}: {error}", step.sql))?;
    let affected = statement
        .execute(params_from_iter(step.args.iter().map(|arg| Bind(*arg))))
        .map_err(|error| format!("{}: {error}", step.sql))?;
    if step.changes {
        Ok(Some(affected as i64))
    } else {
        Ok(None)
    }
}

/// 分页删除没有来源关联的孤儿规则，直到整表扫不到为止。
fn sweep_orphans(transaction: &Transaction, specs: &[OrphanSpec]) -> Result<(), String> {
    for spec in specs {
        loop {
            let ids: Vec<i64> = {
                let mut statement = transaction
                    .prepare(&spec.select_sql)
                    .map_err(|error| error.to_string())?;
                let rows = statement
                    .query_map([spec.select_limit], |row| row.get(0))
                    .map_err(|error| error.to_string())?;
                rows.collect::<rusqlite::Result<Vec<i64>>>()
                    .map_err(|error| error.to_string())?
            };
            if ids.is_empty() {
                break;
            }
            let placeholders = vec!["?"; ids.len()].join(",");
            let sql = format!("{}{placeholders})", spec.delete_prefix);
            transaction
                .execute(&sql, params_from_iter(ids.iter()))
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}

struct Bind<'a>(SqlArg<'a>);

impl ToSql for Bind<'_> {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(match self.0 {
            SqlArg::Null => ToSqlOutput::Owned(SqlValue::Null),
            SqlArg::Int(value) => ToSqlOutput::Owned(SqlValue::Integer(value)),
            SqlArg::Text(value) => ToSqlOutput::Borrowed(ValueRef::Text(value.as_bytes())),
        })
    }
}
