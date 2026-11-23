use std::io;
use std::path::PathBuf;
use std::sync::Arc;

use diting_desktop_api::config::{Config, ConfigStore};
use serde_json::{Map, Value};

use crate::db::SqliteDb;

pub struct SqliteConfigStore {
    db: Arc<SqliteDb>,
    location: PathBuf,
}

impl SqliteConfigStore {
    pub fn new(db: Arc<SqliteDb>) -> Self {
        let location = db.path().to_path_buf();
        Self { db, location }
    }
}

impl ConfigStore for SqliteConfigStore {
    fn load(&self) -> io::Result<Config> {
        let rows = self
            .db
            .read(|connection| {
                let mut statement = connection
                    .prepare("SELECT section, doc FROM config_sections ORDER BY section")?;
                let rows = statement.query_map([], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                })?;
                rows.collect::<rusqlite::Result<Vec<_>>>()
            })
            .map_err(io::Error::other)?;

        if rows.is_empty() {
            let mut config = Config::default();
            config.normalize();
            return Ok(config);
        }

        let mut object = Map::with_capacity(rows.len());
        for (section, doc) in rows {
            match serde_json::from_str::<Value>(&doc) {
                Ok(value) => {
                    object.insert(section, value);
                }
                Err(error) => eprintln!("[存储] 配置分节 {section} 解析失败，已跳过: {error}"),
            }
        }
        let mut config: Config =
            serde_json::from_value(Value::Object(object)).map_err(|error| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("配置分节组合失败: {error}"),
                )
            })?;
        config.normalize();
        Ok(config)
    }

    fn save(&self, config: &Config) -> io::Result<()> {
        let value = serde_json::to_value(config)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
        let Value::Object(object) = value else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "配置序列化结果不是对象",
            ));
        };
        let updated_at = now_ms();
        self.db
            .transaction(|transaction| {
                let mut statement = transaction.prepare(
                    "INSERT INTO config_sections(section, doc, updated_at) VALUES (?1, ?2, ?3)
                     ON CONFLICT(section) DO UPDATE SET doc=excluded.doc, updated_at=excluded.updated_at",
                )?;
                for (section, value) in &object {
                    let doc = serde_json::to_string(value).map_err(|error| {
                        rusqlite::Error::ToSqlConversionFailure(Box::new(error))
                    })?;
                    statement.execute(rusqlite::params![section, doc, updated_at])?;
                }
                Ok(())
            })
            .map_err(io::Error::other)
    }

    fn location(&self) -> PathBuf {
        self.location.clone()
    }
}

fn now_ms() -> i64 {
    chrono::Local::now().timestamp_millis()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_db(tag: &str) -> PathBuf {
        std::env::temp_dir()
            .join(format!(
                "diting-sqlite-config-{tag}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
            ))
            .join("diting.db")
    }

    #[test]
    fn round_trips_every_section() {
        let path = temp_db("roundtrip");
        let db = SqliteDb::open(&path).unwrap();
        let store = SqliteConfigStore::new(Arc::clone(&db));
        let mut config = Config::default();
        config.hosts.ttl = 123;
        config.query_log.retention_days = 9;
        config.web.username = "tester".to_string();
        store.save(&config).unwrap();
        let loaded = store.load().unwrap();
        assert_eq!(loaded.hosts.ttl, 123);
        assert_eq!(loaded.query_log.retention_days, 9);
        assert_eq!(loaded.web.username, "tester");
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn empty_database_returns_defaults() {
        let path = temp_db("empty");
        let db = SqliteDb::open(&path).unwrap();
        let store = SqliteConfigStore::new(db);
        let loaded = store.load().unwrap();
        assert_eq!(loaded.ipc.listen_address, "127.0.0.1:15353");
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
