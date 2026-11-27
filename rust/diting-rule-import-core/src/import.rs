//! 订阅原文 → 规则库的原地导入。
//!
//! 解析、去重与 SQL 生成沿用 `diting-rule-store-core` 的计划，但计划不再经过
//! JSON/FFI/sqflite 通道，而是由本模块在同一个事务里直接执行：
//!
//! * 解析结果不跨 FFI 传输，规则对象直接进入 SQL 执行；
//! * 内容未变化时只做一次纯解析核对哈希，不打开写事务；
//! * 所有写入在一个事务内完成，失败或被删除时整体回滚，不留半套规则；
//! * 提交前重新读取订阅的启用状态，避免导入期间用户切换开关被旧值覆盖。

use std::time::Duration;

use diting_rule_core::models::{ParsedRewriteRule, ParsedUrlRule};
use diting_rule_core::{CategorizedRules, ParsedRule, StreamParse};
use diting_rule_store_core::import::{
    commit_source_plan, import_plan, remove_source_plan, summary,
};
use rusqlite::types::{ToSqlOutput, Value as SqlValue, ValueRef};
use rusqlite::{params_from_iter, Connection, OpenFlags, ToSql, Transaction};
use serde_json::{json, Map, Value};

use crate::probe::{flag, integer, list, text};

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
    execute_steps(&transaction, list(&cleanup, "steps"))?;
    sweep_orphans(&transaction, list(&cleanup, "orphans"))?;

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
    execute_steps(&transaction, list(&commit, "steps"))?;
    sweep_orphans(&transaction, list(&commit, "orphans"))?;
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

        let parsed = chunk_value(chunk);
        let plan = import_plan(
            &parsed,
            context.staging,
            context.kind,
            context.enabled,
            context.chunk_size,
            context.now,
        );
        for batch in &plan.batches {
            let family = text(batch, "family").unwrap_or_default();
            let mut total = 0i64;
            for step in list(batch, "steps") {
                if let Some(changed) = execute_step(transaction, step)? {
                    total += changed;
                }
            }
            let entry = self.counts.entry(family).or_insert_with(|| json!(0));
            *entry = json!(entry.as_i64().unwrap_or(0) + total);
        }
        for (key, value) in summary(&plan, &parsed) {
            let entry = self.parsed.entry(key).or_insert_with(|| json!(0));
            *entry = json!(entry.as_i64().unwrap_or(0) + value.as_i64().unwrap_or(0));
        }
        Ok(())
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

/// 字段名与 Dart 侧 `_ruleJson` / `_rewriteJson` / `_urlJson` 保持一致。
fn chunk_value(chunk: &CategorizedRules) -> Value {
    json!({
        "blockRules": chunk.block_rules.iter().map(rule_json).collect::<Vec<Value>>(),
        "allowRules": chunk.allow_rules.iter().map(rule_json).collect::<Vec<Value>>(),
        "rewriteRules": chunk
            .rewrite_rules
            .iter()
            .map(rewrite_json)
            .collect::<Vec<Value>>(),
        "urlBlockRules": chunk
            .url_block_rules
            .iter()
            .map(url_json)
            .collect::<Vec<Value>>(),
        "urlAllowRules": chunk
            .url_allow_rules
            .iter()
            .map(url_json)
            .collect::<Vec<Value>>(),
        "cosmeticRules": chunk
            .cosmetic_rules
            .iter()
            .map(|rule| json!({
                "domain": rule.domain,
                "selector": rule.selector,
                "rawLine": rule.raw_line,
                "isException": rule.is_exception,
            }))
            .collect::<Vec<Value>>(),
        "duplicateCount": chunk.duplicate_count,
        "invalidCount": chunk.invalid_count,
        "unsupportedCount": chunk.unsupported_count,
        "badfilteredCount": chunk.badfiltered_count,
    })
}

fn rule_json(rule: &ParsedRule) -> Value {
    json!({
        "pattern": rule.pattern,
        "rawLine": rule.raw_line,
        "important": rule.important,
        "appScope": rule.app_scope,
        "appInverted": rule.app_inverted,
        "isWildcard": rule.is_wildcard,
        "denyallow": rule.denyallow,
        "isRegex": rule.is_regex,
        "dnsType": rule.dns_type,
    })
}

fn rewrite_json(rule: &ParsedRewriteRule) -> Value {
    json!({
        "pattern": rule.pattern,
        "targetType": rule.target_type,
        "targetValue": rule.target_value,
        "rawLine": rule.raw_line,
    })
}

fn url_json(rule: &ParsedUrlRule) -> Value {
    json!({
        "pattern": rule.pattern,
        "rawLine": rule.raw_line,
        "isAllow": rule.is_allow,
        "appScope": rule.app_scope,
    })
}

fn execute_steps(transaction: &Transaction, steps: &[Value]) -> Result<(), String> {
    for step in steps {
        execute_step(transaction, step)?;
    }
    Ok(())
}

fn execute_step(transaction: &Transaction, step: &Value) -> Result<Option<i64>, String> {
    let sql = text(step, "sql").ok_or_else(|| "step without sql".to_string())?;
    let args = list(step, "args");
    let mut statement = transaction
        .prepare(&sql)
        .map_err(|error| format!("{sql}: {error}"))?;
    let affected = statement
        .execute(params_from_iter(args.iter().map(SqlArg)))
        .map_err(|error| format!("{sql}: {error}"))?;
    if flag(step, "changes") == Some(true) {
        Ok(Some(affected as i64))
    } else {
        Ok(None)
    }
}

/// 分页删除没有来源关联的孤儿规则，直到整表扫不到为止。
fn sweep_orphans(transaction: &Transaction, specs: &[Value]) -> Result<(), String> {
    for spec in specs {
        let select =
            text(spec, "selectSql").ok_or_else(|| "orphan without selectSql".to_string())?;
        let delete_prefix =
            text(spec, "deletePrefix").ok_or_else(|| "orphan without prefix".to_string())?;
        let select_args = list(spec, "selectArgs");
        loop {
            let ids: Vec<i64> = {
                let mut statement = transaction
                    .prepare(&select)
                    .map_err(|error| error.to_string())?;
                let rows = statement
                    .query_map(params_from_iter(select_args.iter().map(SqlArg)), |row| {
                        row.get(0)
                    })
                    .map_err(|error| error.to_string())?;
                rows.collect::<rusqlite::Result<Vec<i64>>>()
                    .map_err(|error| error.to_string())?
            };
            if ids.is_empty() {
                break;
            }
            let placeholders = vec!["?"; ids.len()].join(",");
            let sql = format!("{delete_prefix}{placeholders})");
            transaction
                .execute(&sql, params_from_iter(ids.iter()))
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}

struct SqlArg<'a>(&'a Value);

impl ToSql for SqlArg<'_> {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(match self.0 {
            Value::Null => ToSqlOutput::Owned(SqlValue::Null),
            Value::Bool(value) => ToSqlOutput::Owned(SqlValue::Integer(i64::from(*value))),
            Value::Number(number) => {
                if let Some(value) = number.as_i64() {
                    ToSqlOutput::Owned(SqlValue::Integer(value))
                } else {
                    ToSqlOutput::Owned(SqlValue::Real(number.as_f64().unwrap_or(0.0)))
                }
            }
            Value::String(value) => ToSqlOutput::Borrowed(ValueRef::Text(value.as_bytes())),
            _ => ToSqlOutput::Owned(SqlValue::Null),
        })
    }
}
