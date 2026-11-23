use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use diting_desktop_api::config::{Config, ConfigStore};
use diting_desktop_api::platform_types::TakeoverState;
use diting_desktop_core::cache::persist::parse_legacy;
use diting_desktop_core::filter::list_checksum;
use diting_desktop_core::querylog::{normalize_status, Record};
use diting_desktop_platform::traits::StateStore;
use rusqlite::{params, OptionalExtension, Transaction};

use crate::config_store::SqliteConfigStore;
use crate::db::SqliteDb;
use crate::querylog_store::insert_record_batch;
use crate::state_store::SqliteStateStore;

const BATCH_LINES: usize = 1000;

#[derive(Debug, Default)]
pub struct MigrationReport {
    pub imported_config: bool,
    pub imported_state: bool,
    pub imported_cache: usize,
    pub imported_lists: usize,
    pub imported_logs: usize,
    pub skipped_logs: usize,
    pub deleted_files: usize,
    pub errors: Vec<String>,
}

pub fn migrate(
    db: &Arc<SqliteDb>,
    config_path: &Path,
    data_dir: &Path,
    include_querylog: bool,
) -> Result<MigrationReport, String> {
    let mut report = MigrationReport::default();
    let config_done = marker(db, config_path)
        .map(|(_, done)| done)
        .unwrap_or(false);
    let legacy_config = if config_done {
        None
    } else {
        read_legacy_config(config_path, &mut report)
    };

    if config_path.is_file() {
        if config_done {
            delete_file(config_path, &mut report);
        } else if let Some(config) = &legacy_config {
            SqliteConfigStore::new(Arc::clone(db))
                .save(config)
                .map_err(|error| format!("导入旧配置失败: {error}"))?;
            mark(db, config_path, "config", 0, true)?;
            delete_file(config_path, &mut report);
            report.imported_config = true;
        } else {
            mark(db, config_path, "config", 0, true)?;
        }
    }

    let effective = legacy_config
        .or_else(|| SqliteConfigStore::new(Arc::clone(db)).load().ok())
        .unwrap_or_default();

    let state_path = resolve_path(
        &effective.takeover.state_file_path,
        data_dir,
        "dns_state.json",
    );
    import_state(db, &state_path, &mut report)?;

    let cache_path = resolve_path(&effective.cache.persist_path, data_dir, "cache.json");
    import_cache(db, &cache_path, &mut report)?;

    let filter_dir = resolve_dir(&effective.filter.data_dir, data_dir, "filters");
    import_filters(db, &filter_dir, &mut report)?;

    let querylog_dir = resolve_dir(&effective.query_log.data_dir, data_dir, "querylog");
    if include_querylog {
        import_querylogs(db, &querylog_dir, &mut report)?;
    }

    cleanup_empty_dir(&filter_dir);
    cleanup_empty_dir(&querylog_dir);
    Ok(report)
}

fn read_legacy_config(path: &Path, report: &mut MigrationReport) -> Option<Config> {
    let bytes = fs::read(path).ok()?;
    match serde_json::from_slice::<Config>(&bytes) {
        Ok(config) => Some(config),
        Err(error) => {
            report
                .errors
                .push(format!("旧配置解析失败 ({}): {error}", path.display()));
            rename_corrupt(path, report);
            None
        }
    }
}

fn import_state(
    db: &Arc<SqliteDb>,
    path: &Path,
    report: &mut MigrationReport,
) -> Result<(), String> {
    if !path.is_file() {
        return Ok(());
    }
    if marker(db, path).map(|(_, done)| done).unwrap_or(false) {
        delete_file(path, report);
        return Ok(());
    }
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) => {
            report
                .errors
                .push(format!("读取接管状态失败 ({}): {error}", path.display()));
            return Ok(());
        }
    };
    let state: TakeoverState = match serde_json::from_slice(&bytes) {
        Ok(state) => state,
        Err(error) => {
            report
                .errors
                .push(format!("旧接管状态解析失败 ({}): {error}", path.display()));
            rename_corrupt(path, report);
            mark(db, path, "state", 0, true)?;
            return Ok(());
        }
    };
    SqliteStateStore::new(Arc::clone(db))
        .save(&state)
        .map_err(|error| format!("导入接管状态失败: {error}"))?;
    mark(db, path, "state", 0, true)?;
    delete_file(path, report);
    report.imported_state = true;
    Ok(())
}

fn import_cache(
    db: &Arc<SqliteDb>,
    path: &Path,
    report: &mut MigrationReport,
) -> Result<(), String> {
    if !path.is_file() {
        return Ok(());
    }
    if marker(db, path).map(|(_, done)| done).unwrap_or(false) {
        delete_file(path, report);
        return Ok(());
    }
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) => {
            report
                .errors
                .push(format!("读取旧缓存失败 ({}): {error}", path.display()));
            return Ok(());
        }
    };
    let snapshot = match parse_legacy(&bytes) {
        Ok(snapshot) => snapshot,
        Err(error) => {
            report
                .errors
                .push(format!("旧缓存解析失败 ({}): {error}", path.display()));
            rename_corrupt(path, report);
            mark(db, path, "cache", 0, true)?;
            return Ok(());
        }
    };
    let saved_at = snapshot.saved_at.max(1);
    db.transaction(|transaction| {
        transaction.execute("DELETE FROM dns_cache", [])?;
        let mut statement = transaction.prepare(
            "INSERT INTO dns_cache(key, domain, qtype, qclass, wire, original_ttl,              created_at, expires_at, stale_until, is_negative, ip_list, hit_count,              last_hit_at, saved_at)              VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)",
        )?;
        for row in &snapshot.rows {
            let ip_list = serde_json::to_string(&row.ip_list)
                .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
            statement.execute(params![
                row.key,
                row.domain,
                i64::from(row.qtype),
                i64::from(row.qclass),
                row.wire,
                i64::from(row.original_ttl),
                row.created_at,
                row.expires_at,
                row.stale_until,
                i64::from(row.is_negative),
                ip_list,
                row.hit_count as i64,
                row.last_hit_at,
                saved_at,
            ])?;
        }
        Ok(())
    })?;
    report.imported_cache += snapshot.rows.len();
    mark(db, path, "cache", 0, true)?;
    delete_file(path, report);
    Ok(())
}

fn import_filters(
    db: &Arc<SqliteDb>,
    dir: &Path,
    report: &mut MigrationReport,
) -> Result<(), String> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Ok(());
    };
    let mut files: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("txt"))
        .collect();
    files.sort();
    for path in files {
        if marker(db, &path).map(|(_, done)| done).unwrap_or(false) {
            delete_file(&path, report);
            continue;
        }
        let data = match fs::read(&path) {
            Ok(data) => data,
            Err(error) => {
                report
                    .errors
                    .push(format!("读取规则源失败 ({}): {error}", path.display()));
                continue;
            }
        };
        let id = path
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
        if id.is_empty() {
            continue;
        }
        let checksum = list_checksum(&data);
        let fetched_at = chrono::Local::now().timestamp_millis();
        db.write(|connection| {
            connection.execute(
                "INSERT INTO filter_contents(list_id, body, checksum, fetched_at)
                 VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(list_id) DO UPDATE SET
                   body=excluded.body, checksum=excluded.checksum, fetched_at=excluded.fetched_at",
                params![id, data, checksum, fetched_at],
            )
        })?;
        mark(db, &path, "filter", 0, true)?;
        delete_file(&path, report);
        report.imported_lists += 1;
    }
    Ok(())
}

fn import_querylogs(
    db: &Arc<SqliteDb>,
    dir: &Path,
    report: &mut MigrationReport,
) -> Result<(), String> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Ok(());
    };
    let mut files: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default();
            name.starts_with("querylog-") && name.ends_with(".jsonl")
        })
        .collect();
    files.sort();
    for path in files {
        import_querylog_file(db, &path, report)?;
    }
    Ok(())
}

fn import_querylog_file(
    db: &Arc<SqliteDb>,
    path: &Path,
    report: &mut MigrationReport,
) -> Result<(), String> {
    let (progress, done) = marker(db, path).unwrap_or((0, false));
    if done {
        delete_file(path, report);
        return Ok(());
    }
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) => {
            report
                .errors
                .push(format!("读取查询日志失败 ({}): {error}", path.display()));
            return Ok(());
        }
    };
    let reader = BufReader::new(file);
    let mut line_no: i64 = 0;
    let mut batch: Vec<Record> = Vec::new();
    for line in reader.lines() {
        let Ok(line) = line else {
            report
                .errors
                .push(format!("读取查询日志行失败 ({})", path.display()));
            break;
        };
        line_no += 1;
        if line_no <= progress {
            continue;
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        match serde_json::from_str::<Record>(trimmed) {
            Ok(mut record) => {
                record.status = normalize_status(&record.status).to_string();
                batch.push(record);
            }
            Err(_) => report.skipped_logs += 1,
        }
        if batch.len() >= BATCH_LINES {
            let written = batch.len();
            write_batch(db, path, &batch, line_no, false)?;
            report.imported_logs += written;
            batch.clear();
        }
    }
    if !batch.is_empty() {
        let written = batch.len();
        write_batch(db, path, &batch, line_no, false)?;
        report.imported_logs += written;
    }
    write_batch(db, path, &[], line_no, true)?;
    delete_file(path, report);
    Ok(())
}

fn write_batch(
    db: &Arc<SqliteDb>,
    path: &Path,
    records: &[Record],
    progress: i64,
    done: bool,
) -> Result<(), String> {
    let source = path_string(path);
    let (size, mtime) = file_meta(path);
    db.transaction(|transaction| {
        insert_record_batch(transaction, records)?;
        write_marker(
            transaction,
            &source,
            "querylog",
            size,
            mtime,
            progress,
            done,
        )?;
        Ok(())
    })
}

fn marker(db: &Arc<SqliteDb>, path: &Path) -> Option<(i64, bool)> {
    let source = path_string(path);
    db.read(|connection| {
        connection
            .query_row(
                "SELECT progress, done FROM legacy_imports WHERE source = ?1",
                params![source],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)? != 0)),
            )
            .optional()
    })
    .ok()
    .flatten()
}

fn mark(
    db: &Arc<SqliteDb>,
    path: &Path,
    kind: &str,
    progress: i64,
    done: bool,
) -> Result<(), String> {
    let source = path_string(path);
    let (size, mtime) = file_meta(path);
    db.write(|connection| {
        connection.execute(
            "INSERT INTO legacy_imports(source, kind, size, mtime, progress, done, imported_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(source) DO UPDATE SET
               size=excluded.size, mtime=excluded.mtime, progress=excluded.progress,
               done=excluded.done, imported_at=excluded.imported_at",
            params![
                source,
                kind,
                size,
                mtime,
                progress,
                i64::from(done),
                chrono::Local::now().timestamp_millis(),
            ],
        )
    })?;
    Ok(())
}

fn write_marker(
    transaction: &Transaction<'_>,
    source: &str,
    kind: &str,
    size: i64,
    mtime: i64,
    progress: i64,
    done: bool,
) -> rusqlite::Result<()> {
    transaction.execute(
        "INSERT INTO legacy_imports(source, kind, size, mtime, progress, done, imported_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(source) DO UPDATE SET
           size=excluded.size, mtime=excluded.mtime, progress=excluded.progress,
           done=excluded.done, imported_at=excluded.imported_at",
        params![
            source,
            kind,
            size,
            mtime,
            progress,
            i64::from(done),
            chrono::Local::now().timestamp_millis(),
        ],
    )?;
    Ok(())
}

fn resolve_path(value: &str, data_dir: &Path, default_name: &str) -> PathBuf {
    if value.trim().is_empty() {
        return data_dir.join(default_name);
    }
    let configured = PathBuf::from(value);
    if configured.is_file() {
        return configured;
    }
    let fallback = data_dir.join(default_name);
    if fallback.is_file() {
        fallback
    } else {
        configured
    }
}

fn resolve_dir(value: &str, data_dir: &Path, default_name: &str) -> PathBuf {
    if value.trim().is_empty() {
        return data_dir.join(default_name);
    }
    let configured = PathBuf::from(value);
    if configured.is_dir() {
        return configured;
    }
    let fallback = data_dir.join(default_name);
    if fallback.is_dir() {
        fallback
    } else {
        configured
    }
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn file_meta(path: &Path) -> (i64, i64) {
    let Ok(metadata) = fs::metadata(path) else {
        return (0, 0);
    };
    let size = metadata.len().min(i64::MAX as u64) as i64;
    let mtime = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_secs().min(i64::MAX as u64) as i64)
        .unwrap_or(0);
    (size, mtime)
}

fn delete_file(path: &Path, report: &mut MigrationReport) {
    match fs::remove_file(path) {
        Ok(()) => report.deleted_files += 1,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => report
            .errors
            .push(format!("删除旧文件失败 ({}): {error}", path.display())),
    }
}

fn rename_corrupt(path: &Path, report: &mut MigrationReport) {
    let mut target = path.as_os_str().to_os_string();
    target.push(".corrupt");
    let target = PathBuf::from(target);
    match fs::rename(path, &target) {
        Ok(()) => report
            .errors
            .push(format!("已保留损坏文件为 {}", target.display())),
        Err(error) => report
            .errors
            .push(format!("重命名损坏文件失败 ({}): {error}", path.display())),
    }
}

fn cleanup_empty_dir(dir: &Path) {
    let _ = fs::remove_dir(dir);
}

#[cfg(test)]
#[path = "migration/tests.rs"]
mod tests;
