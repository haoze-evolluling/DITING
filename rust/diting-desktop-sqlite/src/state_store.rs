use std::path::{Path, PathBuf};
use std::sync::Arc;

use diting_desktop_api::platform_types::TakeoverState;
use diting_desktop_platform::error::{PlatformError, PlatformResult};
use diting_desktop_platform::traits::StateStore;
use rusqlite::{params, OptionalExtension};

use crate::db::SqliteDb;

pub struct SqliteStateStore {
    db: Arc<SqliteDb>,
    path: PathBuf,
}

impl SqliteStateStore {
    pub fn new(db: Arc<SqliteDb>) -> Self {
        let path = db.path().to_path_buf();
        Self { db, path }
    }
}

impl StateStore for SqliteStateStore {
    fn save(&self, state: &TakeoverState) -> PlatformResult<()> {
        let doc = serde_json::to_string(state)
            .map_err(|error| PlatformError::message(format!("序列化接管状态失败: {error}")))?;
        let updated_at = chrono::Local::now().timestamp_millis();
        self.db
            .write(|connection| {
                connection.execute(
                    "INSERT INTO takeover_state(singleton, doc, updated_at) VALUES (1, ?1, ?2)
                     ON CONFLICT(singleton) DO UPDATE SET doc=excluded.doc, updated_at=excluded.updated_at",
                    params![doc, updated_at],
                )
            })
            .map(|_| ())
            .map_err(|error| PlatformError::message(format!("写入接管状态失败: {error}")))
    }

    fn load(&self) -> PlatformResult<Option<TakeoverState>> {
        let doc = self
            .db
            .read(|connection| {
                connection
                    .query_row(
                        "SELECT doc FROM takeover_state WHERE singleton = 1",
                        [],
                        |row| row.get::<_, String>(0),
                    )
                    .optional()
            })
            .map_err(|error| PlatformError::message(format!("读取接管状态失败: {error}")))?;
        match doc {
            Some(doc) => serde_json::from_str(&doc)
                .map(Some)
                .map_err(|error| PlatformError::message(format!("解析接管状态失败: {error}"))),
            None => Ok(None),
        }
    }

    fn clear(&self) -> PlatformResult<()> {
        self.db
            .write(|connection| connection.execute("DELETE FROM takeover_state", []))
            .map(|_| ())
            .map_err(|error| PlatformError::message(format!("清理接管状态失败: {error}")))
    }

    fn file_path(&self) -> &Path {
        &self.path
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_api::platform_types::AdapterState;

    fn temp_db(tag: &str) -> PathBuf {
        std::env::temp_dir()
            .join(format!(
                "diting-sqlite-state-{tag}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
            ))
            .join("diting.db")
    }

    #[test]
    fn saves_loads_and_clears_state() {
        let path = temp_db("roundtrip");
        let db = SqliteDb::open(&path).unwrap();
        let store = SqliteStateStore::new(db);
        let state = TakeoverState {
            active: true,
            pid: 7,
            adapters: vec![AdapterState {
                id: "eth0".into(),
                ipv4_dns: vec!["1.1.1.1".into()],
                ..AdapterState::default()
            }],
            ..TakeoverState::default()
        };
        store.save(&state).unwrap();
        assert_eq!(store.load().unwrap().unwrap().adapters[0].id, "eth0");
        store.clear().unwrap();
        assert!(store.load().unwrap().is_none());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
