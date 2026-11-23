use std::io;
use std::sync::Arc;

use diting_desktop_core::filter::{list_checksum, ListCache};
use rusqlite::{params, OptionalExtension};

use crate::db::SqliteDb;

pub struct SqliteListCache {
    db: Arc<SqliteDb>,
}

impl SqliteListCache {
    pub fn new(db: Arc<SqliteDb>) -> Self {
        Self { db }
    }
}

impl ListCache for SqliteListCache {
    fn read(&self, id: &str) -> Option<Vec<u8>> {
        self.db
            .read(|connection| {
                connection
                    .query_row(
                        "SELECT body FROM filter_contents WHERE list_id = ?1",
                        params![id],
                        |row| row.get::<_, Vec<u8>>(0),
                    )
                    .optional()
            })
            .ok()
            .flatten()
    }

    fn write(&self, id: &str, data: &[u8]) -> io::Result<()> {
        let checksum = list_checksum(data);
        let fetched_at = chrono::Local::now().timestamp_millis();
        self.db
            .write(|connection| {
                connection.execute(
                    "INSERT INTO filter_contents(list_id, body, checksum, fetched_at)
                     VALUES (?1, ?2, ?3, ?4)
                     ON CONFLICT(list_id) DO UPDATE SET
                       body=excluded.body, checksum=excluded.checksum, fetched_at=excluded.fetched_at",
                    params![id, data, checksum, fetched_at],
                )
            })
            .map(|_| ())
            .map_err(io::Error::other)
    }

    fn remove(&self, id: &str) {
        let _ = self.db.write(|connection| {
            connection.execute(
                "DELETE FROM filter_contents WHERE list_id = ?1",
                params![id],
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
                "diting-sqlite-list-{tag}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
            ))
            .join("diting.db")
    }

    #[test]
    fn writes_reads_and_removes_list_bodies() {
        let path = temp_db("roundtrip");
        let db = SqliteDb::open(&path).unwrap();
        let cache = SqliteListCache::new(db);
        cache.write("list-a", b"||ads.example^\n").unwrap();
        assert_eq!(
            cache.read("list-a").as_deref(),
            Some(&b"||ads.example^\n"[..])
        );
        cache.remove("list-a");
        assert!(cache.read("list-a").is_none());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
