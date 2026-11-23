use rusqlite::Connection;

pub const SCHEMA_VERSION: i32 = 1;

const DDL: &str = r#"
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS config_sections (
  section TEXT PRIMARY KEY,
  doc TEXT NOT NULL,
  updated_at INTEGER NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS takeover_state (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  doc TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS dns_cache (
  key BLOB PRIMARY KEY,
  domain BLOB NOT NULL,
  qtype INTEGER NOT NULL,
  qclass INTEGER NOT NULL,
  wire BLOB NOT NULL,
  original_ttl INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  stale_until INTEGER NOT NULL,
  is_negative INTEGER NOT NULL,
  ip_list TEXT NOT NULL,
  hit_count INTEGER NOT NULL,
  last_hit_at INTEGER NOT NULL,
  saved_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_dns_cache_stale ON dns_cache(stale_until);

CREATE TABLE IF NOT EXISTS filter_contents (
  list_id TEXT PRIMARY KEY,
  body BLOB NOT NULL,
  checksum TEXT NOT NULL,
  fetched_at INTEGER NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS query_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  domain TEXT NOT NULL,
  qtype TEXT NOT NULL DEFAULT '',
  client_ip TEXT NOT NULL DEFAULT '',
  client_name TEXT NOT NULL DEFAULT '',
  duration_ms REAL NOT NULL DEFAULT 0,
  rcode TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL,
  cached INTEGER NOT NULL DEFAULT 0,
  ttl INTEGER,
  cache_hit TEXT NOT NULL DEFAULT '',
  blocked INTEGER NOT NULL DEFAULT 0,
  filter_rule TEXT NOT NULL DEFAULT '',
  filter_reason TEXT NOT NULL DEFAULT '',
  protocol TEXT NOT NULL DEFAULT '',
  upstream_provider TEXT NOT NULL DEFAULT '',
  error TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_query_log_ts ON query_log(ts DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_query_log_status_ts ON query_log(status, ts DESC);

CREATE TABLE IF NOT EXISTS web_sessions (
  token TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  client_ip TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_web_sessions_expires ON web_sessions(expires_at);

CREATE TABLE IF NOT EXISTS legacy_imports (
  source TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  progress INTEGER NOT NULL DEFAULT 0,
  done INTEGER NOT NULL DEFAULT 0,
  imported_at INTEGER NOT NULL
) WITHOUT ROWID;
"#;

pub fn migrate(connection: &Connection) -> Result<(), String> {
    let version: i32 = connection
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .map_err(|error| format!("读取数据库版本失败: {error}"))?;
    if version > SCHEMA_VERSION {
        return Err(format!(
            "数据库版本 {version} 高于当前程序支持的 {SCHEMA_VERSION}，请升级程序"
        ));
    }
    if version == 0 {
        connection
            .execute_batch(DDL)
            .map_err(|error| format!("创建数据库表失败: {error}"))?;
        connection
            .execute_batch(&format!("PRAGMA user_version={SCHEMA_VERSION};"))
            .map_err(|error| format!("写入数据库版本失败: {error}"))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_the_schema_once() {
        let connection = Connection::open_in_memory().unwrap();
        migrate(&connection).unwrap();
        migrate(&connection).unwrap();
        let version: i32 = connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, SCHEMA_VERSION);
        let table: String = connection
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='query_log'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(table, "query_log");
    }
}
