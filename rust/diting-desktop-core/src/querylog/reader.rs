//! Reverse JSON-Lines reader for persisted query history.
//!
//! Port of `desktop/service/internal/querylog/reader.go`: files are scanned newest-date first,
//! each file is read backwards in 64 KiB blocks, corrupt lines are skipped, and counting mode
//! keeps scanning after the candidate page is full so `Total` stays stable across offsets.

use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use super::types::{Record, SearchQuery};
use super::writer::{file_date_ms, list_log_files};

const READ_BLOCK_SIZE: usize = 64 * 1024;
const MAX_LINE_SIZE: usize = 64 * 1024;
const DAY_MS: i64 = 24 * 60 * 60 * 1000;

/// Read one file newest → oldest, invoking `visit` per line.
///
/// `visit` returns `true` to continue and `false` to stop. Unparseable (partial / corrupt) lines
/// are silently skipped.
pub(crate) fn read_file_reverse<F>(path: &Path, mut visit: F) -> io::Result<()>
where
    F: FnMut(&Record) -> bool,
{
    let mut file = File::open(path)?;
    let size = file.metadata()?.len();
    if size == 0 {
        return Ok(());
    }

    let mut buffer = vec![0u8; READ_BLOCK_SIZE];
    let mut orphan: Vec<u8> = Vec::new();
    let mut stopped = false;
    let mut pos = size;

    while pos > 0 && !stopped {
        let count = READ_BLOCK_SIZE.min(pos as usize);
        pos -= count as u64;
        file.seek(SeekFrom::Start(pos))?;
        file.read_exact(&mut buffer[..count])?;

        let mut combined = Vec::with_capacity(count + orphan.len());
        combined.extend_from_slice(&buffer[..count]);
        combined.extend_from_slice(&orphan);

        let parts: Vec<&[u8]> = combined.split(|&byte| byte == b'\n').collect();
        orphan.clear();
        if let Some(first) = parts.first() {
            orphan.extend_from_slice(first);
        }
        for line in parts.iter().skip(1).rev() {
            if emit_line(line, &mut visit) {
                stopped = true;
                break;
            }
        }
    }

    if !stopped && !orphan.is_empty() {
        emit_line(&orphan, &mut visit);
    }
    Ok(())
}

/// Parse one line; returns `true` when iteration should stop.
fn emit_line<F>(line: &[u8], visit: &mut F) -> bool
where
    F: FnMut(&Record) -> bool,
{
    let line = trim_ascii_space(line);
    if line.is_empty() || line.len() > MAX_LINE_SIZE {
        return false;
    }
    match serde_json::from_slice::<Record>(line) {
        Ok(record) => !visit(&record),
        Err(_) => false,
    }
}

fn trim_ascii_space(mut bytes: &[u8]) -> &[u8] {
    while let Some((first, rest)) = bytes.split_first() {
        if first.is_ascii_whitespace() {
            bytes = rest;
        } else {
            break;
        }
    }
    while let Some((last, rest)) = bytes.split_last() {
        if last.is_ascii_whitespace() {
            bytes = rest;
        } else {
            break;
        }
    }
    bytes
}

/// Scan `paths` (oldest file first) in reverse, newest records first.
///
/// In counting mode (`need_count`) every match is counted even after `need` candidates were
/// collected; in quick mode scanning stops once `need` is exceeded. Returns the match count seen
/// up to the point scanning stopped.
pub(crate) fn search_files_reverse<F>(
    paths: &[PathBuf],
    query: &SearchQuery,
    need: i64,
    need_count: bool,
    mut collect: F,
) -> i64
where
    F: FnMut(&Record) -> bool,
{
    let mut total = 0i64;
    for path in paths.iter().rev() {
        if query.start_ms > 0 {
            if let Some(file_ms) = file_date_ms(path) {
                if file_ms > 0 && file_ms + DAY_MS <= query.start_ms {
                    continue;
                }
            }
        }
        let mut stopped = false;
        let _ = read_file_reverse(path, |record| {
            if query.start_ms > 0 && record.timestamp < query.start_ms {
                return false;
            }
            if !query.matches(record) {
                return true;
            }
            total += 1;
            if !need_count && need > 0 && total > need {
                return false;
            }
            if collect(record) {
                stopped = true;
                return false;
            }
            true
        });
        if stopped {
            return total;
        }
    }
    total
}

/// File-backed portion of a paginated search (newest first).
///
/// Only records older than the memory ring's oldest timestamp are scanned, so page totals remain
/// exact without double-counting memory hits.
pub(crate) fn search_files(
    dir: &Path,
    query: &SearchQuery,
    mem_total: i64,
    mem_oldest: i64,
) -> (Vec<Record>, i64) {
    let mut file_query = query.clone();
    if mem_oldest > 0 && (file_query.end_ms == 0 || file_query.end_ms > mem_oldest) {
        file_query.end_ms = mem_oldest - 1;
    }

    let need = (query.offset + query.limit - mem_total).max(0);
    let mut hits = Vec::new();
    let paths = list_log_files(dir);
    let total = search_files_reverse(&paths, &file_query, need, true, |record| {
        if hits.len() as i64 >= need {
            return false;
        }
        hits.push(record.clone());
        false
    });
    (hits, total)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::querylog::unique_temp_dir;
    use crate::querylog::writer::{FILE_PREFIX, FILE_SUFFIX};
    use chrono::{Local, TimeZone};
    use std::path::Path;

    fn write_jsonl(path: &Path, records: &[Record]) {
        use std::io::Write;
        let mut file = File::create(path).expect("create");
        for record in records {
            let line = serde_json::to_vec(record).expect("serialize");
            file.write_all(&line).expect("write");
            file.write_all(b"\n").expect("write");
        }
    }

    fn record(timestamp: i64, domain: &str) -> Record {
        Record {
            timestamp,
            domain: domain.into(),
            status: super::super::types::STATUS_ALLOWED.into(),
            ..Record::default()
        }
    }

    #[test]
    fn reads_newest_first() {
        let dir = unique_temp_dir("reader-order");
        let path = dir.join(format!("{FILE_PREFIX}20261013{FILE_SUFFIX}"));
        write_jsonl(
            &path,
            &[
                record(1000, "a.com"),
                record(2000, "b.com"),
                record(3000, "c.com"),
            ],
        );

        let mut got = Vec::new();
        read_file_reverse(&path, |record| {
            got.push(record.timestamp);
            true
        })
        .expect("read");
        assert_eq!(got, vec![3000, 2000, 1000]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn skips_corrupt_lines() {
        let dir = unique_temp_dir("reader-corrupt");
        let path = dir.join(format!("{FILE_PREFIX}20261013{FILE_SUFFIX}"));
        std::fs::write(
            &path,
            "{\"ts\":1000,\"domain\":\"a.com\",\"status\":\"allowed\"}\nthis is not json\n{\"ts\":2000,\"domain\":\"b.com\",\"status\":\"allowed\"}\n",
        )
        .expect("write");

        let mut got = Vec::new();
        read_file_reverse(&path, |record| {
            got.push(record.timestamp);
            true
        })
        .expect("read");
        assert_eq!(got, vec![2000, 1000]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn search_early_stop_across_files() {
        let dir = unique_temp_dir("reader-early");
        let day1 = dir.join(format!("{FILE_PREFIX}20261012{FILE_SUFFIX}"));
        let day2 = dir.join(format!("{FILE_PREFIX}20261013{FILE_SUFFIX}"));
        write_jsonl(&day1, &[record(1000, "old1.com"), record(2000, "old2.com")]);
        write_jsonl(&day2, &[record(3000, "new1.com"), record(4000, "new2.com")]);
        let paths = vec![day1, day2];

        let mut hits = Vec::new();
        search_files_reverse(
            &paths,
            &SearchQuery {
                limit: 10,
                ..SearchQuery::default()
            },
            2,
            false,
            |record| {
                hits.push(record.timestamp);
                hits.len() >= 2
            },
        );
        assert_eq!(hits, vec![4000, 3000]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn file_date_ms_matches_local_midnight() {
        let path = Path::new("x").join(format!("{FILE_PREFIX}20261013{FILE_SUFFIX}"));
        let expected = Local
            .with_ymd_and_hms(2026, 10, 13, 0, 0, 0)
            .single()
            .expect("midnight")
            .timestamp_millis();
        assert_eq!(file_date_ms(&path), Some(expected));
        assert_eq!(file_date_ms(Path::new("garbage.txt")), None);
    }

    #[test]
    fn total_is_stable_across_offsets() {
        let dir = unique_temp_dir("reader-total");
        let path = dir.join(format!("{FILE_PREFIX}20261012{FILE_SUFFIX}"));
        let records: Vec<Record> = (0..100)
            .map(|index| record(1000 + index, "h.test"))
            .collect();
        write_jsonl(&path, &records);
        let paths = vec![path];

        for offset in [0i64, 50, 200] {
            let need = offset + 10;
            let mut hits = Vec::new();
            let total = search_files_reverse(
                &paths,
                &SearchQuery {
                    limit: 10,
                    ..SearchQuery::default()
                },
                need,
                true,
                |record| {
                    if (hits.len() as i64) < need {
                        hits.push(record.timestamp);
                    }
                    false
                },
            );
            assert_eq!(total, 100, "offset={offset}");
            assert!(hits.len() as i64 <= need);
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
}
