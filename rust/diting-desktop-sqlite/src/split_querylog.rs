use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use diting_desktop_api::config::paths::{
    DEFAULT_QUERY_LOG_DB_FILE_NAME, DEFAULT_QUERY_LOG_DIR_NAME,
};
use diting_desktop_core::querylog::{Config, QueryLogStorage, Record, SearchQuery, SearchResult};

use crate::db::SqliteDb;
use crate::querylog_store::SqliteQueryLogStorage;

struct ActiveStore {
    db_path: PathBuf,
    store: Arc<SqliteQueryLogStorage>,
}

/// 支持冷热分离与运行期路径热切换的 SQLite 查询日志存储：
/// - 当 `config.data_dir` 与主数据库同目录（桌面端默认 `<data_dir>/querylog`）时直接复用主库 `diting.db`；
/// - 当 `config.data_dir` 指向独立目录（例如 OpenWrt 默认 `/tmp/diting` 或外置磁盘 `/mnt/...`）时，
///   单独打开 `<data_dir>/querylog.db`，避免高频日志写入磨损主配置所在的路由器闪存。
pub struct RoutedSqliteQueryLogStorage {
    primary_db: Arc<SqliteDb>,
    active: RwLock<Option<ActiveStore>>,
}

impl RoutedSqliteQueryLogStorage {
    pub fn new(primary_db: Arc<SqliteDb>, config: &Config) -> Self {
        let active = open_target(&primary_db, config);
        Self {
            primary_db,
            active: RwLock::new(active),
        }
    }

    pub fn current_db_path(&self) -> Option<PathBuf> {
        self.active
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(|entry| entry.db_path.clone())
    }

    fn current_store(&self) -> Option<Arc<SqliteQueryLogStorage>> {
        self.active
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(|entry| Arc::clone(&entry.store))
    }
}

fn resolve_target_db_path(primary_path: &Path, data_dir: &str) -> PathBuf {
    let trimmed = data_dir.trim();
    if trimmed.is_empty() {
        return primary_path.to_path_buf();
    }
    let dir = Path::new(trimmed);
    if dir
        .extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("db") || ext.eq_ignore_ascii_case("sqlite"))
    {
        return dir.to_path_buf();
    }
    if let Some(primary_dir) = primary_path.parent() {
        let colocated_default = primary_dir.join(DEFAULT_QUERY_LOG_DIR_NAME);
        if same_path(dir, primary_dir) || same_path(dir, &colocated_default) {
            return primary_path.to_path_buf();
        }
    }
    dir.join(DEFAULT_QUERY_LOG_DB_FILE_NAME)
}

fn same_path(left: &Path, right: &Path) -> bool {
    if left == right {
        return true;
    }
    #[cfg(windows)]
    {
        left.to_string_lossy()
            .replace('\\', "/")
            .eq_ignore_ascii_case(&right.to_string_lossy().replace('\\', "/"))
    }
    #[cfg(not(windows))]
    {
        false
    }
}

fn open_target(primary_db: &Arc<SqliteDb>, config: &Config) -> Option<ActiveStore> {
    let target_path = resolve_target_db_path(primary_db.path(), &config.data_dir);
    let db = if same_path(&target_path, primary_db.path()) {
        Arc::clone(primary_db)
    } else {
        match SqliteDb::open(&target_path) {
            Ok(db) => db,
            Err(error) => {
                eprintln!(
                    "[存储] 打开独立查询日志库失败 ({})，降级为仅内存日志: {error}",
                    target_path.display()
                );
                return None;
            }
        }
    };
    Some(ActiveStore {
        db_path: target_path,
        store: Arc::new(SqliteQueryLogStorage::new(db, config)),
    })
}

impl QueryLogStorage for RoutedSqliteQueryLogStorage {
    fn append(&self, record: Record) -> bool {
        match self.current_store() {
            Some(store) => store.append(record),
            None => false,
        }
    }

    fn search(&self, query: &SearchQuery) -> Option<SearchResult> {
        self.current_store()?.search(query)
    }

    fn search_older(
        &self,
        query: &SearchQuery,
        mem_total: i64,
        mem_oldest: i64,
    ) -> (Vec<Record>, i64) {
        match self.current_store() {
            Some(store) => store.search_older(query, mem_total, mem_oldest),
            None => (Vec::new(), 0),
        }
    }

    fn recent(&self, since_ms: i64, limit: usize) -> Vec<Record> {
        match self.current_store() {
            Some(store) => store.recent(since_ms, limit),
            None => Vec::new(),
        }
    }

    fn configure(&self, config: &Config) {
        let desired_path = resolve_target_db_path(self.primary_db.path(), &config.data_dir);
        let unchanged = {
            let guard = self
                .active
                .read()
                .unwrap_or_else(|error| error.into_inner());
            guard
                .as_ref()
                .is_some_and(|entry| same_path(&entry.db_path, &desired_path))
        };
        if unchanged {
            if let Some(store) = self.current_store() {
                store.configure(config);
            }
            return;
        }

        let previous = {
            let mut guard = self
                .active
                .write()
                .unwrap_or_else(|error| error.into_inner());
            guard.take()
        };
        if let Some(prev) = previous {
            let _ = prev.store.close();
        }
        let next = open_target(&self.primary_db, config);
        *self
            .active
            .write()
            .unwrap_or_else(|error| error.into_inner()) = next;
    }

    fn clear(&self) -> io::Result<()> {
        match self.current_store() {
            Some(store) => store.clear(),
            None => Ok(()),
        }
    }

    fn close(&self) -> io::Result<()> {
        let previous = {
            let mut guard = self
                .active
                .write()
                .unwrap_or_else(|error| error.into_inner());
            guard.take()
        };
        match previous {
            Some(entry) => entry.store.close(),
            None => Ok(()),
        }
    }

    fn is_persistent(&self) -> bool {
        self.current_store()
            .is_some_and(|store| store.is_persistent())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_root(tag: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "diting-split-ql-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ))
    }

    #[test]
    fn colocated_uses_primary_and_external_splits_cleanly() {
        let root = temp_root("split");
        let etc_dir = root.join("etc");
        let tmp_dir = root.join("tmp");
        let mnt_dir = root.join("mnt");
        let primary = SqliteDb::open(etc_dir.join("diting.db")).unwrap();

        let colocated_cfg = Config {
            file_enabled: true,
            data_dir: etc_dir.join("querylog").to_string_lossy().into_owned(),
            ..Config::default()
        };
        let storage = RoutedSqliteQueryLogStorage::new(Arc::clone(&primary), &colocated_cfg);
        assert_eq!(storage.current_db_path().as_deref(), Some(primary.path()));

        let volatile_cfg = Config {
            file_enabled: true,
            data_dir: tmp_dir.to_string_lossy().into_owned(),
            ..Config::default()
        };
        storage.configure(&volatile_cfg);
        assert_eq!(storage.current_db_path(), Some(tmp_dir.join("querylog.db")));
        assert!(storage.append(Record {
            timestamp: 1234,
            domain: "openwrt.org".to_string(),
            status: "allowed".to_string(),
            ..Record::default()
        }));

        let external_cfg = Config {
            file_enabled: true,
            data_dir: mnt_dir.to_string_lossy().into_owned(),
            ..Config::default()
        };
        storage.configure(&external_cfg);
        assert_eq!(storage.current_db_path(), Some(mnt_dir.join("querylog.db")));
        storage.close().unwrap();
        drop(primary);
        let _ = std::fs::remove_dir_all(&root);
    }
}
