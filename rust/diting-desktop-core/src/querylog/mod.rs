mod collector;
mod reader;
mod ring;
mod storage;
mod types;
mod writer;

use std::io;
#[cfg(test)]
use std::path::PathBuf;
use std::sync::{Arc, Mutex, RwLock};

use chrono::Local;

use ring::Ring;
pub use storage::{FileQueryLogStorage, QueryLogStorage};

pub use collector::Collector;
pub use types::{
    default_data_dir, default_querylog_dir, normalize_status, Config, HourPoint, NameCount, Record,
    SearchQuery, SearchResult, Summary, DEFAULT_MAX_ENTRIES, DEFAULT_RETENTION_DAYS,
    MAX_ENTRIES_CAP, MAX_SEARCH_LIMIT, RETENTION_DAYS_CAP, STATUS_ALLOWED, STATUS_BLOCKED,
    STATUS_CACHED, STATUS_ERROR, STATUS_STALE,
};

const HYDRATE_WINDOW_MS: i64 = 24 * 60 * 60 * 1000;
const HYDRATE_LIMIT: usize = 500_000;

struct Inner {
    cfg: Config,
    ring: Arc<Ring>,
    collector: Arc<Collector>,
    storage: Arc<dyn QueryLogStorage>,
}

pub struct QueryLog {
    inner: RwLock<Inner>,
    lifecycle: Mutex<()>,
}

impl QueryLog {
    pub fn new(config: Config) -> Self {
        Self::with_storage(config, None)
    }

    pub fn with_storage(config: Config, storage: Option<Arc<dyn QueryLogStorage>>) -> Self {
        let mut cfg = config;
        cfg.normalize(default_querylog_dir());
        let ring = Arc::new(Ring::new(cfg.max_entries));
        let collector = Arc::new(Collector::new());
        let storage = storage.unwrap_or_else(|| Arc::new(FileQueryLogStorage::new(&cfg)));
        storage.configure(&cfg);
        let log = Self {
            inner: RwLock::new(Inner {
                cfg,
                ring: Arc::clone(&ring),
                collector: Arc::clone(&collector),
                storage,
            }),
            lifecycle: Mutex::new(()),
        };
        log.hydrate();
        log
    }

    fn hydrate(&self) {
        let (storage, ring, collector) = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            (
                Arc::clone(&inner.storage),
                Arc::clone(&inner.ring),
                Arc::clone(&inner.collector),
            )
        };
        if !storage.is_persistent() {
            return;
        }
        let since = Local::now().timestamp_millis() - HYDRATE_WINDOW_MS;
        for record in storage.recent(since, HYDRATE_LIMIT) {
            ring.append(record.clone());
            collector.record(&record);
        }
    }

    pub fn record(&self, mut record: Record) {
        let (enabled, log_clients, ring, collector, storage) = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            (
                inner.cfg.enabled,
                inner.cfg.log_clients,
                Arc::clone(&inner.ring),
                Arc::clone(&inner.collector),
                Arc::clone(&inner.storage),
            )
        };
        if !enabled {
            return;
        }

        record.status = normalize_status(&record.status).to_string();
        if record.timestamp <= 0 {
            record.timestamp = Local::now().timestamp_millis();
        }
        if !log_clients {
            record.client_ip.clear();
            record.client_name.clear();
        }

        ring.append(record.clone());
        collector.record(&record);
        storage.append(record);
    }

    pub fn search(&self, mut query: SearchQuery) -> SearchResult {
        if query.limit <= 0 || query.limit > i64::from(MAX_SEARCH_LIMIT) {
            query.limit = i64::from(MAX_SEARCH_LIMIT);
        }
        if query.offset < 0 {
            query.offset = 0;
        }

        let (ring, storage) = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            (Arc::clone(&inner.ring), Arc::clone(&inner.storage))
        };

        let (memory, mem_total) = ring.search_all(&query);
        let mem_total = mem_total as i64;

        if !query.include_file {
            return ring_result(memory, mem_total, &query);
        }
        if let Some(result) = storage.search(&query) {
            return result;
        }
        if !storage.is_persistent() || query.offset + query.limit < mem_total {
            return ring_result(memory, mem_total, &query);
        }

        let (file_hits, file_total) =
            storage.search_older(&query, mem_total, ring.oldest_timestamp());
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

    pub fn stats(&self) -> Summary {
        Arc::clone(&self.collector_ref()).summary()
    }

    pub fn per_hour(&self) -> Vec<HourPoint> {
        self.collector_ref().per_hour()
    }

    pub fn top_domains(&self, n: i64) -> Vec<NameCount> {
        self.collector_ref().top_domains(n)
    }

    pub fn top_blocked_domains(&self, n: i64) -> Vec<NameCount> {
        self.collector_ref().top_blocked_domains(n)
    }

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

    pub fn config(&self) -> Config {
        self.inner
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .cfg
            .clone()
    }

    pub fn configure(&self, config: Config) {
        let _lifecycle = self.lifecycle.lock().unwrap_or_else(|e| e.into_inner());
        let mut cfg = config;
        cfg.normalize(default_querylog_dir());

        let storage = {
            let mut inner = self.inner.write().unwrap_or_else(|e| e.into_inner());
            inner.cfg = cfg.clone();
            inner.ring.resize(cfg.max_entries);
            Arc::clone(&inner.storage)
        };
        storage.configure(&cfg);
    }

    pub fn clear(&self, remove_files: bool) -> io::Result<()> {
        let (ring, collector, storage) = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            (
                Arc::clone(&inner.ring),
                Arc::clone(&inner.collector),
                Arc::clone(&inner.storage),
            )
        };
        ring.clear();
        collector.clear();
        if remove_files {
            return storage.clear();
        }
        Ok(())
    }

    pub fn close(&self) -> io::Result<()> {
        let _lifecycle = self.lifecycle.lock().unwrap_or_else(|e| e.into_inner());
        let storage = {
            let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
            Arc::clone(&inner.storage)
        };
        storage.close()
    }

    pub fn is_file_enabled(&self) -> bool {
        self.inner
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .storage
            .is_persistent()
    }

    pub fn is_persistent(&self) -> bool {
        self.is_file_enabled()
    }
}

fn ring_result(memory: Vec<Record>, total: i64, query: &SearchQuery) -> SearchResult {
    let start = (query.offset as usize).min(memory.len());
    let end = (start + query.limit as usize).min(memory.len());
    SearchResult {
        total,
        entries: memory[start..end].to_vec(),
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
        assert_eq!(result.total, 0);
    }
}
