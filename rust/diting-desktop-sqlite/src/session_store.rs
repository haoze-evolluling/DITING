use std::sync::Arc;

use diting_desktop_ipc::auth::SessionInfo;
use diting_desktop_ipc::session::SessionStore;
use rusqlite::params;

use crate::db::SqliteDb;

pub struct SqliteSessionStore {
    db: Arc<SqliteDb>,
}

impl SqliteSessionStore {
    pub fn new(db: Arc<SqliteDb>) -> Self {
        Self { db }
    }
}

impl SessionStore for SqliteSessionStore {
    fn load(&self) -> Vec<SessionInfo> {
        self.db
            .read(|connection| {
                let mut statement = connection.prepare(
                    "SELECT token, username, client_ip, created_at, expires_at FROM web_sessions",
                )?;
                let rows = statement.query_map([], |row| {
                    Ok(SessionInfo {
                        token: row.get(0)?,
                        username: row.get(1)?,
                        client_ip: row.get(2)?,
                        created_at_unix: row.get(3)?,
                        expires_at_unix: row.get(4)?,
                    })
                })?;
                rows.collect::<rusqlite::Result<Vec<_>>>()
            })
            .unwrap_or_else(|error| {
                eprintln!("[存储] 管理端会话恢复失败: {error}");
                Vec::new()
            })
    }

    fn insert(&self, session: &SessionInfo) {
        let result = self.db.write(|connection| {
            connection.execute(
                "INSERT INTO web_sessions(token, username, client_ip, created_at, expires_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(token) DO UPDATE SET
                   username=excluded.username, client_ip=excluded.client_ip,
                   created_at=excluded.created_at, expires_at=excluded.expires_at",
                params![
                    session.token,
                    session.username,
                    session.client_ip,
                    session.created_at_unix,
                    session.expires_at_unix,
                ],
            )
        });
        if let Err(error) = result {
            eprintln!("[存储] 管理端会话写入失败: {error}");
        }
    }

    fn remove(&self, token: &str) {
        let _ = self.db.write(|connection| {
            connection.execute("DELETE FROM web_sessions WHERE token = ?1", params![token])
        });
    }

    fn clear(&self) {
        let _ = self
            .db
            .write(|connection| connection.execute("DELETE FROM web_sessions", []));
    }

    fn prune(&self, now_unix: i64) {
        let _ = self.db.write(|connection| {
            connection.execute(
                "DELETE FROM web_sessions WHERE expires_at <= ?1",
                params![now_unix],
            )
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn temp_db(tag: &str) -> PathBuf {
        std::env::temp_dir()
            .join(format!(
                "diting-sqlite-session-{tag}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
            ))
            .join("diting.db")
    }

    fn session(token: &str, expires_at: i64) -> SessionInfo {
        SessionInfo {
            token: token.to_string(),
            username: "admin".to_string(),
            client_ip: "127.0.0.1".to_string(),
            created_at_unix: 1,
            expires_at_unix: expires_at,
        }
    }

    #[test]
    fn inserts_loads_prunes_and_removes() {
        let path = temp_db("roundtrip");
        let db = SqliteDb::open(&path).unwrap();
        let store = SqliteSessionStore::new(db);
        store.insert(&session("a", 100));
        store.insert(&session("b", 200));
        assert_eq!(store.load().len(), 2);
        store.prune(150);
        let loaded = store.load();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].token, "b");
        store.remove("b");
        assert!(store.load().is_empty());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
