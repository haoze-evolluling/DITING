use std::path::PathBuf;
use std::sync::Arc;

use diting_desktop_api::config::CacheConfig;
use diting_desktop_core::cache::persist::{entry_from_row, PersistRow, PersistStatus};
use diting_desktop_core::cache::CachePersistence;
use diting_dns_cache_core::Cache;
use rusqlite::{params, Row};

use crate::db::SqliteDb;

pub struct SqliteCachePersistence {
    db: Arc<SqliteDb>,
    location: PathBuf,
}

impl SqliteCachePersistence {
    pub fn new(db: Arc<SqliteDb>) -> Self {
        let location = db.path().to_path_buf();
        Self { db, location }
    }
}

impl CachePersistence for SqliteCachePersistence {
    fn save(&self, cache: &Cache, _config: &CacheConfig) -> Result<PersistStatus, String> {
        let entries = cache.export();
        let saved_at = now_ms();
        let count = entries.len();
        self.db.transaction(|transaction| {
            transaction.execute("DELETE FROM dns_cache", [])?;
            let mut statement = transaction.prepare(
                "INSERT INTO dns_cache(key, domain, qtype, qclass, wire, original_ttl,                  created_at, expires_at, stale_until, is_negative, ip_list, hit_count,                  last_hit_at, saved_at)                  VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)",
            )?;
            for entry in &entries {
                let ip_list = serde_json::to_string(&entry.ip_list)
                    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
                statement.execute(params![
                    entry.key,
                    entry.domain,
                    i64::from(entry.qtype),
                    i64::from(entry.qclass),
                    entry.wire,
                    i64::from(entry.original_ttl),
                    entry.created_at_ms,
                    entry.expires_at_ms,
                    entry.stale_until_ms,
                    i64::from(entry.is_negative),
                    ip_list,
                    entry.hit_count as i64,
                    entry.last_hit_at_ms,
                    saved_at,
                ])?;
            }
            Ok(())
        })?;
        let _ = self.db.incremental_vacuum();
        Ok(PersistStatus {
            entries: count,
            max_entries: cache.capacity(),
            saved_at,
        })
    }

    fn load(&self, cache: &Cache, _config: &CacheConfig) -> Result<usize, String> {
        let rows = self.db.read(|connection| {
            let mut statement = connection.prepare(
                "SELECT key, domain, qtype, qclass, wire, original_ttl, created_at,                  expires_at, stale_until, is_negative, ip_list, hit_count, last_hit_at                  FROM dns_cache",
            )?;
            let rows = statement.query_map([], row_to_persist)?;
            rows.collect::<rusqlite::Result<Vec<_>>>()
        })?;
        let entries = rows.into_iter().filter_map(entry_from_row).collect();
        Ok(cache.import(entries))
    }

    fn location(&self, _config: &CacheConfig) -> String {
        self.location.to_string_lossy().into_owned()
    }
}

fn row_to_persist(row: &Row<'_>) -> rusqlite::Result<PersistRow> {
    let ip_list: String = row.get(10)?;
    Ok(PersistRow {
        key: row.get(0)?,
        domain: row.get(1)?,
        qtype: row.get::<_, i64>(2)?.max(0) as u16,
        qclass: row.get::<_, i64>(3)?.max(0) as u16,
        wire: row.get(4)?,
        original_ttl: row.get::<_, i64>(5)?.max(0) as u32,
        created_at: row.get(6)?,
        expires_at: row.get(7)?,
        stale_until: row.get(8)?,
        is_negative: row.get::<_, i64>(9)? != 0,
        ip_list: serde_json::from_str(&ip_list).unwrap_or_default(),
        hit_count: row.get::<_, i64>(11)?.max(0) as u64,
        last_hit_at: row.get(12)?,
    })
}

fn now_ms() -> i64 {
    chrono::Local::now().timestamp_millis()
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_cache_core::policy::{Config, TtlMode};
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord};

    fn temp_db(tag: &str) -> PathBuf {
        std::env::temp_dir()
            .join(format!(
                "diting-sqlite-cache-{tag}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
            ))
            .join("diting.db")
    }

    fn response(domain: &str) -> Vec<u8> {
        let query = MessageBuilder::query(domain, 1, 1).finish().unwrap();
        MessageBuilder::reply_to(&query)
            .unwrap()
            .push_answer(ResourceRecord::new(
                domain,
                1,
                1,
                60,
                RData::A(std::net::Ipv4Addr::new(1, 2, 3, 4)),
            ))
            .finish()
            .unwrap()
    }

    #[test]
    fn round_trips_cache_entries() {
        let path = temp_db("roundtrip");
        let db = SqliteDb::open(&path).unwrap();
        let store = SqliteCachePersistence::new(Arc::clone(&db));
        let cache = Cache::new(Config {
            enabled: true,
            mode: TtlMode::LimitMaxTtl,
            ..Config::default()
        });
        let query = MessageBuilder::query("example.com", 1, 1).finish().unwrap();
        assert!(cache.put(&query, &response("example.com")));
        let status = store.save(&cache, &CacheConfig::default()).unwrap();
        assert_eq!(status.entries, 1);
        cache.clear();
        assert_eq!(store.load(&cache, &CacheConfig::default()).unwrap(), 1);
        assert!(cache.get(&query, true).is_some());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
