use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use rusqlite::Connection;

use crate::schema;

pub struct SqliteDb {
    path: PathBuf,
    writer: Mutex<Connection>,
    reader: Mutex<Connection>,
}

impl SqliteDb {
    pub fn open(path: impl Into<PathBuf>) -> Result<Arc<Self>, String> {
        let path = path.into();
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            std::fs::create_dir_all(parent)
                .map_err(|error| format!("创建数据库目录失败 ({}): {error}", parent.display()))?;
        }
        precreate_private_file(&path);

        let writer = Connection::open(&path)
            .map_err(|error| format!("打开数据库失败 ({}): {error}", path.display()))?;
        configure_writer(&writer)?;
        schema::migrate(&writer)?;

        let reader = Connection::open(&path)
            .map_err(|error| format!("打开数据库读连接失败 ({}): {error}", path.display()))?;
        configure_reader(&reader)?;

        secure_db_files(&path);
        Ok(Arc::new(Self {
            path,
            writer: Mutex::new(writer),
            reader: Mutex::new(reader),
        }))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn write<T>(
        &self,
        action: impl FnOnce(&mut Connection) -> rusqlite::Result<T>,
    ) -> Result<T, String> {
        let mut connection = self
            .writer
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        action(&mut connection).map_err(|error| format!("数据库写入失败: {error}"))
    }

    pub fn read<T>(
        &self,
        action: impl FnOnce(&Connection) -> rusqlite::Result<T>,
    ) -> Result<T, String> {
        let connection = self
            .reader
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        action(&connection).map_err(|error| format!("数据库读取失败: {error}"))
    }

    pub fn transaction<T>(
        &self,
        action: impl FnOnce(&rusqlite::Transaction<'_>) -> rusqlite::Result<T>,
    ) -> Result<T, String> {
        let mut connection = self
            .writer
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let transaction = connection
            .transaction()
            .map_err(|error| format!("开启数据库事务失败: {error}"))?;
        let outcome = action(&transaction).map_err(|error| format!("数据库事务失败: {error}"))?;
        transaction
            .commit()
            .map_err(|error| format!("提交数据库事务失败: {error}"))?;
        Ok(outcome)
    }

    pub fn checkpoint(&self) -> Result<(), String> {
        self.write(|connection| connection.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);"))
            .map(|_| ())
    }

    pub fn incremental_vacuum(&self) -> Result<(), String> {
        self.write(|connection| connection.execute_batch("PRAGMA incremental_vacuum;"))
            .map(|_| ())
    }
}

fn configure_writer(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            "PRAGMA busy_timeout=5000;\n\
             PRAGMA foreign_keys=ON;\n\
             PRAGMA temp_store=MEMORY;\n\
             PRAGMA synchronous=NORMAL;\n\
             PRAGMA wal_autocheckpoint=1000;\n\
             PRAGMA journal_size_limit=67108864;\n\
             PRAGMA auto_vacuum=INCREMENTAL;",
        )
        .map_err(|error| format!("初始化数据库连接失败: {error}"))?;
    let mode = connection
        .query_row("PRAGMA journal_mode=WAL", [], |row| row.get::<_, String>(0))
        .unwrap_or_default();
    if !mode.eq_ignore_ascii_case("wal") {
        let fallback = connection
            .query_row("PRAGMA journal_mode=DELETE", [], |row| {
                row.get::<_, String>(0)
            })
            .unwrap_or_default();
        eprintln!("[存储] WAL 不可用，已回退 journal_mode={fallback}");
    }
    Ok(())
}

fn configure_reader(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch("PRAGMA busy_timeout=5000;\nPRAGMA query_only=ON;")
        .map_err(|error| format!("初始化数据库读连接失败: {error}"))
}

#[cfg(unix)]
fn precreate_private_file(path: &Path) {
    use std::os::unix::fs::OpenOptionsExt;
    let _ = std::fs::OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .mode(0o600)
        .open(path);
}

#[cfg(not(unix))]
fn precreate_private_file(_path: &Path) {}

#[cfg(unix)]
fn secure_db_files(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let secure = |target: &Path| {
        let _ = std::fs::set_permissions(target, std::fs::Permissions::from_mode(0o600));
    };
    secure(path);
    for suffix in ["-wal", "-shm"] {
        let target = PathBuf::from(format!("{}{suffix}", path.display()));
        if target.exists() {
            secure(&target);
        }
    }
}

#[cfg(not(unix))]
fn secure_db_files(_path: &Path) {}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_db(tag: &str) -> PathBuf {
        std::env::temp_dir()
            .join(format!(
                "diting-sqlite-{tag}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
            ))
            .join("diting.db")
    }

    #[test]
    fn opens_schema_and_round_trips_meta() {
        let path = temp_db("open");
        let db = SqliteDb::open(&path).unwrap();
        db.write(|connection| {
            connection.execute(
                "INSERT OR REPLACE INTO meta(key, value) VALUES ('test', 'ok')",
                [],
            )
        })
        .unwrap();
        let value: String = db
            .read(|connection| {
                connection.query_row("SELECT value FROM meta WHERE key='test'", [], |row| {
                    row.get(0)
                })
            })
            .unwrap();
        assert_eq!(value, "ok");
        db.checkpoint().unwrap();
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn rejects_newer_schema_version() {
        let path = temp_db("version");
        let db = SqliteDb::open(&path).unwrap();
        db.write(|connection| connection.execute_batch("PRAGMA user_version=99;"))
            .unwrap();
        drop(db);
        let error = match SqliteDb::open(&path) {
            Ok(_) => panic!("newer schema version should be rejected"),
            Err(error) => error,
        };
        assert!(error.contains("版本"), "{error}");
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
