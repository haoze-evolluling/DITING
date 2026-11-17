//! Query history and runtime statistics.
//!
//! Port of `desktop/service/internal/querylog`:
//!   - a fixed-capacity in-memory ring for fast recent lookups;
//!   - 24-hour rolling per-hour statistics (totals, blocked, cache hits, Top-N);
//!   - daily JSON-Lines persistence with retention cleanup.
//!
//! `QueryLog::record` sits on the DNS hot path: it takes one short read lock, then works on
//! cloned `Arc`s and only ever performs a non-blocking enqueue to the writer.

mod collector;
mod reader;
mod ring;
mod types;
mod writer;

use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use chrono::Local;

use ring::Ring;
use writer::Writer;

pub use collector::Collector;
pub use types::{
    default_data_dir, default_querylog_dir, normalize_status, Config, HourPoint, NameCount, Record,
    SearchQuery, SearchResult, Summary, DEFAULT_MAX_ENTRIES, DEFAULT_RETENTION_DAYS,
    MAX_ENTRIES_CAP, MAX_SEARCH_LIMIT, RETENTION_DAYS_CAP, STATUS_ALLOWED, STATUS_BLOCKED,
    STATUS_CACHED, STATUS_ERROR, STATUS_STALE,
};

struct Inner {
    cfg: Config,
    ring: Arc<Ring>,
    collector: Arc<Collector>,
    writer: Option<Arc<Writer>>,
    /// Persistence is usable (directory writable); otherwise the facade is memory-only.
    file_ok: bool,
}

/// Query-history and statistics facade. All methods are thread-safe.
pub struct QueryLog {
    inner: RwLock<Inner>,
}

impl QueryLog {
    /// Create a facade. An unwritable data directory degrades to memory-only mode.
    pub fn new(config: Config) -> Self {
        let mut cfg = config;
        cfg.normalize(default_querylog_dir());
        let ring = Arc::new(Ring::new(cfg.max_entries));
        let collector = Arc::new(Collector::new());
        let (writer, file_ok) = build_writer(&cfg);
        Self {
            inner: RwLock::new(Inner {
                cfg,
                ring,
                collector,
                writer,
                file_ok,
            }),
        }
    }

    /// Record one query (DNS hot path). No-op while disabled.
    pub fn record(&self, mut record: Record) {
        let (enabled, log_clients, ring, collector, writer, file_ok) = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            (
                inner.cfg.enabled,
                inner.cfg.log_clients,
                Arc::clone(&inner.ring),
                Arc::clone(&inner.collector),
                inner.writer.clone(),
                inner.file_ok,
            )
        };
        if !enabled {
            return;
        }

        record.status = normalize_status(&record.status).to_string();
        if record.timestamp <= 0 {
            // Fill once so the ring, stats and persistence agree on the timestamp.
            record.timestamp = Local::now().timestamp_millis();
        }
        if !log_clients {
            record.client_ip.clear();
            record.client_name.clear();
        }

        if file_ok {
            if let Some(writer) = writer {
                ring.append(record.clone());
                collector.record(&record);
                writer.enqueue(record);
                return;
            }
        }
        collector.record(&record);
        ring.append(record);
    }

    /// Search recent (ring) and, when requested, older (file) history. Newest first.
    pub fn search(&self, mut query: SearchQuery) -> SearchResult {
        if query.limit <= 0 || query.limit > i64::from(MAX_SEARCH_LIMIT) {
            query.limit = i64::from(MAX_SEARCH_LIMIT);
        }
        if query.offset < 0 {
            query.offset = 0;
        }

        let (ring, writer, file_ok) = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            (Arc::clone(&inner.ring), inner.writer.clone(), inner.file_ok)
        };

        let (memory, mem_total) = ring.search_all(&query);
        let mem_total = mem_total as i64;

        let (file_hits, file_total) = if query.include_file
            && file_ok
            && query.offset + query.limit + 1 > mem_total
        {
            match writer {
                Some(writer) => {
                    reader::search_files(writer.dir(), &query, mem_total, ring.oldest_timestamp())
                }
                None => (Vec::new(), 0),
            }
        } else {
            (Vec::new(), 0)
        };

        let total = mem_total + file_total;
        let mut combined = file_hits;
        combined.extend(memory);
        let start = (query.offset as usize).min(combined.len());
        let end = (start + query.limit as usize).min(combined.len());
        SearchResult {
            total,
            entries: combined[start..end].to_vec(),
        }
    }

    /// Summary for the rolling 24-hour window.
    pub fn stats(&self) -> Summary {
        Arc::clone(&self.collector_ref()).summary()
    }

    /// Per-hour trend for the last 24 hours, zero-filled.
    pub fn per_hour(&self) -> Vec<HourPoint> {
        self.collector_ref().per_hour()
    }

    /// Most queried domains.
    pub fn top_domains(&self, n: i64) -> Vec<NameCount> {
        self.collector_ref().top_domains(n)
    }

    /// Most blocked domains.
    pub fn top_blocked_domains(&self, n: i64) -> Vec<NameCount> {
        self.collector_ref().top_blocked_domains(n)
    }

    /// Busiest clients.
    pub fn top_clients(&self, n: i64) -> Vec<NameCount> {
        self.collector_ref().top_clients(n)
    }

    fn collector_ref(&self) -> Arc<Collector> {
        Arc::clone(
            &self
                .inner
                .read()
                .unwrap_or_else(|e| e.into_inner())
                .collector,
        )
    }

    /// Current configuration copy.
    pub fn config(&self) -> Config {
        self.inner
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .cfg
            .clone()
    }

    /// Apply a configuration update: resize the ring and restart the writer when needed.
    pub fn configure(&self, config: Config) {
        let mut cfg = config;
        cfg.normalize(default_querylog_dir());

        let mut inner = self.inner.write().unwrap_or_else(|e| e.into_inner());
        inner.cfg = cfg.clone();
        inner.ring.resize(cfg.max_entries);

        let need_reinit = inner.writer.is_none() != !cfg.file_enabled
            || inner.writer.as_ref().is_some_and(|writer| {
                writer.dir() != Path::new(&cfg.data_dir)
                    || writer.retention_days() != cfg.retention_days
            });
        if !need_reinit {
            return;
        }

        if let Some(writer) = inner.writer.take() {
            let _ = writer.close();
        }
        let (writer, file_ok) = build_writer(&cfg);
        inner.writer = writer;
        inner.file_ok = file_ok;
    }

    /// Clear memory and statistics; optionally close the handle and delete persisted files.
    pub fn clear(&self, remove_files: bool) -> io::Result<()> {
        let (ring, collector, writer, file_ok) = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            (
                Arc::clone(&inner.ring),
                Arc::clone(&inner.collector),
                inner.writer.clone(),
                inner.file_ok,
            )
        };
        ring.clear();
        collector.clear();
        if remove_files && file_ok {
            if let Some(writer) = writer {
                return writer.clear();
            }
        }
        Ok(())
    }

    /// Stop the writer after draining and flushing the queue.
    pub fn close(&self) -> io::Result<()> {
        let writer = {
            let mut inner = self.inner.write().unwrap_or_else(|e| e.into_inner());
            inner.file_ok = false;
            inner.writer.take()
        };
        match writer {
            Some(writer) => writer.close(),
            None => Ok(()),
        }
    }

    /// Whether persisted history is currently available.
    pub fn is_file_enabled(&self) -> bool {
        self.inner.read().unwrap_or_else(|e| e.into_inner()).file_ok
    }
}

fn build_writer(cfg: &Config) -> (Option<Arc<Writer>>, bool) {
    if !cfg.file_enabled {
        return (None, false);
    }
    match Writer::new(PathBuf::from(&cfg.data_dir), cfg.retention_days) {
        Ok(writer) => (Some(Arc::new(writer)), true),
        Err(_) => (None, false),
    }
}

#[cfg(test)]
pub(crate) fn unique_temp_dir(tag: &str) -> PathBuf {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let dir = std::env::temp_dir().join(format!(
        "diting-querylog-{tag}-{}-{nanos}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::querylog::writer::{FILE_PREFIX, FILE_SUFFIX};
    use chrono::{Local, TimeZone};
    use std::fs;

    fn memory_config() -> Config {
        Config {
            file_enabled: false,
            ..Config::default()
        }
    }

    fn record(domain: &str, status: &str) -> Record {
        Record {
            domain: domain.into(),
            qtype: "A".into(),
            status: status.into(),
            ..Record::default()
        }
    }

    #[test]
    fn record_and_search_newest_first() {
        let q = QueryLog::new(memory_config());
        for _ in 0..5 {
            q.record(record("d.com", STATUS_ALLOWED));
        }
        q.record(Record {
            blocked: true,
            ..record("ads.com", STATUS_BLOCKED)
        });

        let result = q.search(SearchQuery {
            limit: 100,
            ..SearchQuery::default()
        });
        assert_eq!(result.total, 6);
        assert_eq!(result.entries.len(), 6);
        assert_eq!(result.entries[0].domain, "ads.com");

        let blocked = q.search(SearchQuery {
            status: STATUS_BLOCKED.into(),
            limit: 100,
            ..SearchQuery::default()
        });
        assert_eq!(blocked.total, 1);
    }

    #[test]
    fn disabled_records_nothing() {
        let q = QueryLog::new(Config {
            enabled: false,
            file_enabled: false,
            ..Config::default()
        });
        q.record(record("a.com", STATUS_ALLOWED));
        assert_eq!(q.search(SearchQuery::default()).total, 0);
        assert_eq!(q.stats().queries, 0);
    }

    #[test]
    fn privacy_strips_client_fields() {
        let q = QueryLog::new(Config {
            file_enabled: false,
            log_clients: false,
            ..Config::default()
        });
        q.record(Record {
            client_ip: "192.168.1.9".into(),
            client_name: "laptop".into(),
            ..record("a.com", STATUS_ALLOWED)
        });
        let result = q.search(SearchQuery::default());
        assert_eq!(result.entries.len(), 1);
        assert!(result.entries[0].client_ip.is_empty());
        assert!(result.entries[0].client_name.is_empty());
        assert!(q.top_clients(10).is_empty());
    }

    #[test]
    fn status_and_timestamp_are_normalized() {
        let q = QueryLog::new(memory_config());
        q.record(Record {
            status: "weird".into(),
            ..Record {
                domain: "a.com".into(),
                ..Record::default()
            }
        });
        let result = q.search(SearchQuery::default());
        assert_eq!(result.entries[0].status, STATUS_ALLOWED);
        assert!(result.entries[0].timestamp > 0);
    }

    #[test]
    fn configure_resizes_ring() {
        let q = QueryLog::new(Config {
            file_enabled: false,
            max_entries: 10,
            ..Config::default()
        });
        for _ in 0..8 {
            q.record(record("d.com", STATUS_ALLOWED));
        }
        q.configure(Config {
            file_enabled: false,
            max_entries: 3,
            ..Config::default()
        });
        assert_eq!(
            q.search(SearchQuery {
                limit: 100,
                ..SearchQuery::default()
            })
            .total,
            3
        );
    }

    #[test]
    fn close_persists_and_clear_removes_files() {
        let dir = unique_temp_dir("facade-clear");
        let cfg = Config {
            data_dir: dir.to_string_lossy().into_owned(),
            ..Config::default()
        };
        let q = QueryLog::new(cfg.clone());
        assert!(q.is_file_enabled());
        q.record(record("persist.com", STATUS_ALLOWED));
        q.close().expect("close");

        let files: Vec<PathBuf> = fs::read_dir(&dir)
            .expect("read dir")
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(super::writer::is_log_file_name)
            })
            .collect();
        assert!(!files.is_empty(), "expected a persisted file");
        let content = fs::read_to_string(&files[0]).expect("read");
        assert!(content.contains("persist.com"));

        let q2 = QueryLog::new(cfg);
        let result = q2.search(SearchQuery {
            limit: 10,
            include_file: true,
            ..SearchQuery::default()
        });
        assert!(result.total > 0, "expected persisted history");

        q2.clear(true).expect("clear");
        let after = q2.search(SearchQuery {
            limit: 10,
            include_file: true,
            ..SearchQuery::default()
        });
        assert_eq!(after.total, 0);
        let remaining = fs::read_dir(&dir).expect("read dir").count();
        assert_eq!(remaining, 0, "expected all log files removed");
        q2.close().expect("close");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn search_falls_back_to_files() {
        let dir = unique_temp_dir("facade-files");
        let now = Local::now().timestamp_millis();
        let earlier = now - 3 * 24 * 60 * 60 * 1000;
        let day = Local
            .timestamp_millis_opt(earlier)
            .single()
            .expect("local")
            .format(writer::DAY_LAYOUT)
            .to_string();
        let path = dir.join(format!("{FILE_PREFIX}{day}{FILE_SUFFIX}"));
        let seeded = [
            Record {
                timestamp: earlier,
                domain: "old1.com".into(),
                status: STATUS_ALLOWED.into(),
                ..Record::default()
            },
            Record {
                timestamp: earlier + 1000,
                domain: "old2.com".into(),
                status: STATUS_ALLOWED.into(),
                ..Record::default()
            },
        ];
        let mut content = String::new();
        for record in &seeded {
            content.push_str(&serde_json::to_string(record).expect("serialize"));
            content.push('\n');
        }
        fs::write(&path, content).expect("seed");

        let q = QueryLog::new(Config {
            data_dir: dir.to_string_lossy().into_owned(),
            max_entries: 2,
            ..Config::default()
        });
        q.record(record("new.com", STATUS_ALLOWED));

        let result = q.search(SearchQuery {
            limit: 50,
            include_file: true,
            ..SearchQuery::default()
        });
        assert!(result.total >= 3, "got total={}", result.total);

        let memory_only = q.search(SearchQuery {
            limit: 50,
            include_file: false,
            ..SearchQuery::default()
        });
        assert_eq!(memory_only.total, 1);

        q.close().expect("close");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn stats_and_top_lists() {
        let q = QueryLog::new(memory_config());
        q.record(Record {
            client_ip: "10.0.0.1".into(),
            duration_ms: 10.0,
            ..record("a.com", STATUS_ALLOWED)
        });
        q.record(Record {
            client_ip: "10.0.0.1".into(),
            duration_ms: 20.0,
            ..record("a.com", STATUS_ALLOWED)
        });
        q.record(Record {
            client_ip: "10.0.0.2".into(),
            duration_ms: 30.0,
            blocked: true,
            ..record("b.com", STATUS_BLOCKED)
        });

        let summary = q.stats();
        assert_eq!(summary.queries, 3);
        assert_eq!(summary.blocked, 1);
        assert_eq!(summary.forwarded, 2);
        assert!((summary.avg_response_ms - 20.0).abs() < 1e-9);

        let tops = q.top_domains(10);
        assert_eq!(tops.len(), 2);
        assert_eq!(tops[0].name, "a.com");
        assert_eq!(tops[0].count, 2);

        let blocked = q.top_blocked_domains(10);
        assert_eq!(blocked.len(), 1);
        assert_eq!(blocked[0].name, "b.com");

        let clients = q.top_clients(10);
        assert_eq!(clients.len(), 2);
        assert_eq!(clients[0].name, "10.0.0.1");
        assert_eq!(clients[0].count, 2);
    }

    #[test]
    fn search_limit_is_capped() {
        let q = QueryLog::new(memory_config());
        let result = q.search(SearchQuery {
            limit: 10_000,
            ..SearchQuery::default()
        });
        assert!(result.entries.is_empty());
        // The cap is enforced before paging; nothing to observe but no overflow.
        assert_eq!(result.total, 0);
    }
}
