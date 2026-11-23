use std::collections::VecDeque;
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TrySendError};
use std::sync::{Arc, Mutex, RwLock};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use chrono::Local;
use diting_desktop_core::querylog::{
    normalize_status, Config, QueryLogStorage, Record, SearchQuery, SearchResult, MAX_SEARCH_LIMIT,
};
use rusqlite::types::Value;
use rusqlite::{params, params_from_iter, Row};

use crate::db::SqliteDb;

const QUEUE_SIZE: usize = 4096;
const FLUSH_LINES: usize = 256;
const FLUSH_INTERVAL: Duration = Duration::from_secs(1);
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60);
const DAY_MS: i64 = 24 * 60 * 60 * 1000;
const SELECT_COLUMNS: &str = "ts, domain, qtype, client_ip, client_name, duration_ms, rcode,              status, cached, ttl, cache_hit, blocked, filter_rule, filter_reason, protocol,              upstream_provider, error";

#[derive(Clone, Copy)]
struct WriterConfig {
    enabled: bool,
    retention_days: i32,
    max_entries: i32,
}

pub struct SqliteQueryLogStorage {
    db: Arc<SqliteDb>,
    sender: Mutex<Option<SyncSender<Record>>>,
    handle: Mutex<Option<JoinHandle<()>>>,
    config: Arc<RwLock<WriterConfig>>,
    closed: AtomicBool,
}

impl SqliteQueryLogStorage {
    pub fn new(db: Arc<SqliteDb>, config: &Config) -> Self {
        let (sender, receiver) = sync_channel(QUEUE_SIZE);
        let writer_config = Arc::new(RwLock::new(WriterConfig {
            enabled: config.file_enabled,
            retention_days: config.retention_days,
            max_entries: config.max_entries,
        }));
        let handle = std::thread::Builder::new()
            .name("diting-querylog-sqlite".into())
            .spawn({
                let db = Arc::clone(&db);
                let writer_config = Arc::clone(&writer_config);
                move || run_writer(db, receiver, writer_config)
            })
            .ok();
        Self {
            db,
            sender: Mutex::new(Some(sender)),
            handle: Mutex::new(handle),
            config: writer_config,
            closed: AtomicBool::new(false),
        }
    }

    fn config(&self) -> WriterConfig {
        *self
            .config
            .read()
            .unwrap_or_else(|error| error.into_inner())
    }
}

impl QueryLogStorage for SqliteQueryLogStorage {
    fn append(&self, record: Record) -> bool {
        if self.closed.load(Ordering::Relaxed) || !self.config().enabled {
            return false;
        }
        let sender = self
            .sender
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        match sender.as_ref() {
            Some(sender) => match sender.try_send(record) {
                Ok(()) => true,
                Err(TrySendError::Full(_)) | Err(TrySendError::Disconnected(_)) => false,
            },
            None => false,
        }
    }

    fn search(&self, query: &SearchQuery) -> Option<SearchResult> {
        let limit = query.limit.clamp(1, i64::from(MAX_SEARCH_LIMIT));
        let offset = query.offset.max(0);
        let (where_sql, values) = search_filter(query);
        let total = self
            .db
            .read(|connection| {
                connection.query_row(
                    &format!("SELECT COUNT(*) FROM query_log WHERE {where_sql}"),
                    params_from_iter(values.iter().cloned()),
                    |row| row.get::<_, i64>(0),
                )
            })
            .ok()?;
        let entries = self
            .db
            .read(|connection| {
                let sql = format!(
                    "SELECT {SELECT_COLUMNS} FROM query_log WHERE {where_sql}                      ORDER BY ts DESC, id DESC LIMIT ? OFFSET ?"
                );
                let mut statement = connection.prepare(&sql)?;
                let mut all = values.clone();
                all.push(Value::Integer(limit));
                all.push(Value::Integer(offset));
                let rows = statement.query_map(params_from_iter(all), record_from_row)?;
                rows.collect::<rusqlite::Result<Vec<_>>>()
            })
            .ok()?;
        Some(SearchResult { total, entries })
    }

    fn search_older(
        &self,
        _query: &SearchQuery,
        _mem_total: i64,
        _mem_oldest: i64,
    ) -> (Vec<Record>, i64) {
        (Vec::new(), 0)
    }

    fn recent(&self, since_ms: i64, limit: usize) -> Vec<Record> {
        self.db
            .read(|connection| {
                let sql = format!(
                    "SELECT {SELECT_COLUMNS} FROM query_log WHERE ts >= ?1                      ORDER BY ts ASC LIMIT ?2"
                );
                let mut statement = connection.prepare(&sql)?;
                let rows = statement.query_map(params![since_ms, limit as i64], record_from_row)?;
                rows.collect::<rusqlite::Result<Vec<_>>>()
            })
            .unwrap_or_else(|error| {
                eprintln!("[存储] 查询日志恢复失败: {error}");
                Vec::new()
            })
    }

    fn configure(&self, config: &Config) {
        let mut current = self
            .config
            .write()
            .unwrap_or_else(|error| error.into_inner());
        current.enabled = config.file_enabled;
        current.retention_days = config.retention_days;
        current.max_entries = config.max_entries;
    }

    fn clear(&self) -> io::Result<()> {
        self.db
            .write(|connection| connection.execute("DELETE FROM query_log", []))
            .map_err(io::Error::other)?;
        let _ = self.db.incremental_vacuum();
        Ok(())
    }

    fn close(&self) -> io::Result<()> {
        if self.closed.swap(true, Ordering::SeqCst) {
            return Ok(());
        }
        self.sender
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        let handle = self
            .handle
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        match handle {
            Some(handle) => handle
                .join()
                .map_err(|_| io::Error::other("查询日志 SQLite 写入线程异常退出")),
            None => Ok(()),
        }
    }

    fn is_persistent(&self) -> bool {
        true
    }
}

impl Drop for SqliteQueryLogStorage {
    fn drop(&mut self) {
        let _ = self.close();
    }
}

fn run_writer(db: Arc<SqliteDb>, receiver: Receiver<Record>, config: Arc<RwLock<WriterConfig>>) {
    let mut pending: VecDeque<Record> = VecDeque::new();
    let mut last_flush = Instant::now();
    let mut last_cleanup = Instant::now() - CLEANUP_INTERVAL;
    loop {
        match receiver.recv_timeout(Duration::from_millis(200)) {
            Ok(record) => {
                pending.push_back(record);
                if pending.len() >= FLUSH_LINES {
                    flush(&db, &mut pending);
                    last_flush = Instant::now();
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                if !pending.is_empty() && last_flush.elapsed() >= FLUSH_INTERVAL {
                    flush(&db, &mut pending);
                    last_flush = Instant::now();
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                if !pending.is_empty() {
                    flush(&db, &mut pending);
                }
                return;
            }
        }
        if last_cleanup.elapsed() >= CLEANUP_INTERVAL {
            cleanup(
                &db,
                *config.read().unwrap_or_else(|error| error.into_inner()),
            );
            last_cleanup = Instant::now();
        }
    }
}

fn flush(db: &SqliteDb, pending: &mut VecDeque<Record>) {
    let records: Vec<Record> = pending.drain(..).collect();
    if records.is_empty() {
        return;
    }
    let result = db.transaction(|transaction| insert_record_batch(transaction, &records));
    if let Err(error) = result {
        eprintln!(
            "[存储] 查询日志写入失败，已丢弃 {} 条: {error}",
            records.len()
        );
    }
}

pub(crate) fn insert_record_batch(
    transaction: &rusqlite::Transaction<'_>,
    records: &[Record],
) -> rusqlite::Result<()> {
    let mut statement = transaction.prepare(
        "INSERT INTO query_log(ts, domain, qtype, client_ip, client_name, duration_ms,          rcode, status, cached, ttl, cache_hit, blocked, filter_rule, filter_reason,          protocol, upstream_provider, error)          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)",
    )?;
    for record in records {
        statement.execute(params![
            record.timestamp,
            record.domain,
            record.qtype,
            record.client_ip,
            record.client_name,
            record.duration_ms,
            record.rcode,
            record.status,
            i64::from(record.cached),
            record.ttl.map(i64::from),
            record.cache_hit,
            i64::from(record.blocked),
            record.filter_rule,
            record.filter_reason,
            record.protocol,
            record.upstream_provider,
            record.error,
        ])?;
    }
    Ok(())
}

fn cleanup(db: &SqliteDb, config: WriterConfig) {
    let cutoff = Local::now().timestamp_millis() - i64::from(config.retention_days) * DAY_MS;
    let result = db.write(|connection| {
        connection.execute("DELETE FROM query_log WHERE ts < ?1", params![cutoff])?;
        if config.max_entries > 0 {
            connection.execute(
                "DELETE FROM query_log WHERE id IN (SELECT id FROM query_log                      ORDER BY ts DESC, id DESC LIMIT -1 OFFSET ?1)",
                params![i64::from(config.max_entries)],
            )?;
        }
        Ok(())
    });
    if let Err(error) = result {
        eprintln!("[存储] 查询日志清理失败: {error}");
        return;
    }
    let _ = db.incremental_vacuum();
}

fn search_filter(query: &SearchQuery) -> (String, Vec<Value>) {
    let mut clauses = vec!["1=1".to_string()];
    let mut values = Vec::new();
    if query.start_ms > 0 {
        clauses.push("ts >= ?".to_string());
        values.push(Value::Integer(query.start_ms));
    }
    if query.end_ms > 0 {
        clauses.push("ts <= ?".to_string());
        values.push(Value::Integer(query.end_ms));
    }
    if !query.status.is_empty() {
        clauses.push("status = ?".to_string());
        values.push(Value::Text(normalize_status(&query.status).to_string()));
    }
    if !query.qtype.is_empty() {
        clauses.push("LOWER(qtype) = LOWER(?)".to_string());
        values.push(Value::Text(query.qtype.clone()));
    }
    if !query.rcode.is_empty() {
        clauses.push("LOWER(rcode) = LOWER(?)".to_string());
        values.push(Value::Text(query.rcode.clone()));
    }
    if !query.domain.is_empty() {
        clauses.push("LOWER(domain) LIKE ? ESCAPE '\\'".to_string());
        values.push(Value::Text(format!(
            "%{}%",
            escape_like(&query.domain.to_lowercase())
        )));
    }
    if !query.client.is_empty() {
        let needle = format!("%{}%", escape_like(&query.client.to_lowercase()));
        clauses.push(
            "(LOWER(client_ip) LIKE ? ESCAPE '\\' OR LOWER(client_name) LIKE ? ESCAPE '\\')"
                .to_string(),
        );
        values.push(Value::Text(needle.clone()));
        values.push(Value::Text(needle));
    }
    (clauses.join(" AND "), values)
}

fn escape_like(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn record_from_row(row: &Row<'_>) -> rusqlite::Result<Record> {
    let ttl: Option<i64> = row.get(9)?;
    Ok(Record {
        timestamp: row.get(0)?,
        domain: row.get(1)?,
        qtype: row.get(2)?,
        client_ip: row.get(3)?,
        client_name: row.get(4)?,
        duration_ms: row.get(5)?,
        rcode: row.get(6)?,
        status: row.get(7)?,
        cached: row.get::<_, i64>(8)? != 0,
        ttl: ttl.map(|value| value.max(0) as u32),
        cache_hit: row.get(10)?,
        blocked: row.get::<_, i64>(11)? != 0,
        filter_rule: row.get(12)?,
        filter_reason: row.get(13)?,
        protocol: row.get(14)?,
        upstream_provider: row.get(15)?,
        error: row.get(16)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_core::querylog::Config as QueryConfig;
    use std::path::PathBuf;

    fn temp_db(tag: &str) -> PathBuf {
        std::env::temp_dir()
            .join(format!(
                "diting-sqlite-querylog-{tag}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
            ))
            .join("diting.db")
    }

    fn record(ts: i64, domain: &str, status: &str) -> Record {
        Record {
            timestamp: ts,
            domain: domain.to_string(),
            status: status.to_string(),
            client_ip: "192.168.1.9".to_string(),
            ..Record::default()
        }
    }

    #[test]
    fn appends_searches_and_clears() {
        let path = temp_db("search");
        let db = SqliteDb::open(&path).unwrap();
        let config = QueryConfig {
            file_enabled: true,
            ..QueryConfig::default()
        };
        let store = SqliteQueryLogStorage::new(Arc::clone(&db), &config);
        assert!(store.append(record(1000, "a.com", "allowed")));
        assert!(store.append(record(2000, "b.com", "blocked")));
        store.close().unwrap();
        let result = store
            .search(&SearchQuery {
                limit: 10,
                ..SearchQuery::default()
            })
            .unwrap();
        assert_eq!(result.total, 2);
        assert_eq!(result.entries[0].domain, "b.com");
        assert_eq!(store.recent(0, 10).len(), 2);
        store.clear().unwrap();
        assert_eq!(store.recent(0, 10).len(), 0);
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
