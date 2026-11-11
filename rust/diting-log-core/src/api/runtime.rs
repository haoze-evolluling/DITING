//! The runtime-log capture group: the file listing and export document, the `logcat` plan and byte
//! budget, and the `dns_cache` projection.
//!
//! These three Kotlin classes are the last of the `log` package and they are mostly I/O, so the
//! payloads here are deliberately thin: a listing in, a listing out; a line in, a budget out.

use crate::capture::{self, Session};
use crate::mirror::{self, Entry as MirrorEntry};
use crate::payload::{Reader, Writer};
use crate::store::{self, Entry, Section};

/// `u32 count | rows(string name, i64 last_modified, i64 length)`.
fn read_entries(reader: &mut Reader<'_>) -> Option<Vec<Entry>> {
    let count = reader.u32()? as usize;
    let mut entries = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        entries.push(Entry {
            name: reader.string()?,
            last_modified: reader.i64()?,
            length: reader.i64()?,
        });
    }
    Some(entries)
}

fn write_entries(writer: &mut Writer, entries: &[Entry]) {
    writer.u32(entries.len() as u32);
    for entry in entries {
        writer.string(&entry.name);
        writer.i64(entry.last_modified);
        writer.i64(entry.length);
    }
}

/// One directory listing; answers the `.log` files newest-first plus how many a trim keeps.
pub fn store_index(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let entries = read_entries(&mut reader)?;
    if !reader.finish() {
        return None;
    }
    let index = store::index(entries);
    let mut writer = Writer::new();
    writer.u32(index.keep as u32);
    write_entries(&mut writer, &index.files);
    Some(writer.into_vec())
}

/// `u32 count | rows(string name, u8 hasContent, string content) | string crash | string exportedAt`.
pub fn store_document(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut sections = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        let name = reader.string()?;
        let content = match reader.u8()? {
            0 => None,
            1 => Some(reader.string()?),
            _ => return None,
        };
        sections.push(Section { name, content });
    }
    let crash = reader.string()?;
    let exported_at = reader.string()?;
    if !reader.finish() {
        return None;
    }
    let mut writer = Writer::new();
    match store::document(&sections, &crash, &exported_at) {
        None => writer.u8(0),
        Some(text) => {
            writer.u8(1);
            writer.string(&text);
        }
    }
    Some(writer.into_vec())
}

/// The two constants the capture loop needs before it starts a `logcat`.
pub fn capture_plan(pid: i32) -> Vec<u8> {
    let mut writer = Writer::new();
    writer.i64(capture::WATCH_INTERVAL_MS);
    let attempts = capture::commands(pid);
    writer.u32(attempts.len() as u32);
    for attempt in &attempts {
        writer.u32(attempt.len() as u32);
        for part in attempt {
            writer.string(part);
        }
    }
    writer.into_vec()
}

/// `string line`; answers `i64 written | u8 rotate`.
pub fn capture_line(session: &Session, payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let line = reader.string()?;
    if !reader.finish() {
        return None;
    }
    let cost = session.on_line(&line);
    let mut writer = Writer::new();
    writer.i64(cost.written);
    writer.u8(if cost.rotate { 1 } else { 0 });
    Some(writer.into_vec())
}

/// The projection's three numbers.
pub fn mirror_layout() -> Vec<u8> {
    let layout = mirror::layout();
    let mut writer = Writer::new();
    writer.i64(layout.max_rows);
    writer.i64(layout.initial_delay_ms);
    writer.i64(layout.interval_ms);
    writer.into_vec()
}

/// `u32 count | rows(...)` in and out; the answer adds the two constant columns.
pub fn mirror_rows(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut entries = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        entries.push(MirrorEntry {
            key: reader.string()?,
            query_name: reader.string()?,
            query_type: reader.i32()?,
            query_class: reader.i32()?,
            created_at: reader.i64()?,
            expires_at: reader.i64()?,
            last_hit_at: reader.i64()?,
            hit_count: reader.i64()?,
            original_ttl_seconds: reader.i64()?,
            response_size: reader.i32()?,
        });
    }
    if !reader.finish() {
        return None;
    }

    let mut writer = Writer::new();
    writer.u32(entries.len() as u32);
    for entry in entries {
        let row = mirror::project(entry);
        // `u32 count | rows(u32 length | bytes)`: `DnsCacheMirror` binds one blob per row.
        writer.blob(&pack_mirror_row(&row));
    }
    Some(writer.into_vec())
}

fn pack_mirror_row(row: &mirror::Row) -> Vec<u8> {
    let mut writer = Writer::new();
    writer.string(&row.entry.key);
    writer.string(&row.entry.query_name);
    writer.i32(row.entry.query_type);
    writer.i32(row.entry.query_class);
    writer.i64(row.entry.created_at);
    writer.i64(row.entry.expires_at);
    writer.i64(row.entry.last_hit_at);
    writer.i64(row.entry.hit_count);
    writer.i64(row.entry.original_ttl_seconds);
    writer.string(row.ttl_offsets);
    writer.blob(&row.response);
    writer.i32(row.entry.response_size);
    writer.into_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entries_payload(entries: &[(&str, i64, i64)]) -> Vec<u8> {
        let mut writer = Writer::new();
        writer.u32(entries.len() as u32);
        for (name, last_modified, length) in entries {
            writer.string(name);
            writer.i64(*last_modified);
            writer.i64(*length);
        }
        writer.into_vec()
    }

    #[test]
    fn the_index_filters_sorts_and_counts_the_survivors() {
        let answer = store_index(&entries_payload(&[
            ("a.log", 1, 10),
            (".capture", 9, 1),
            ("b.log", 3, 20),
        ]))
        .unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u32(), Some(2)); // keep, both fit
        assert_eq!(reader.u32(), Some(2)); // listing count
        assert_eq!(reader.string().as_deref(), Some("b.log"));
        assert_eq!(reader.i64(), Some(3));
        assert_eq!(reader.i64(), Some(20));
        assert_eq!(reader.string().as_deref(), Some("a.log"));
        assert_eq!(reader.i64(), Some(1));
        assert_eq!(reader.i64(), Some(10));
        assert!(reader.finish());
    }

    #[test]
    fn the_document_payload_round_trips_both_outcomes() {
        let mut writer = Writer::new();
        writer.u32(0);
        writer.string("");
        writer.string("stamp");
        let none = store_document(&writer.into_vec()).unwrap();
        assert_eq!(none, vec![0]);

        let mut writer = Writer::new();
        writer.u32(2);
        writer.string("runtime-1.log");
        writer.u8(1);
        writer.string("body");
        writer.string("runtime-2.log");
        writer.u8(0); // unreadable: no content follows
        writer.string("crash block");
        writer.string("stamp");
        let answer = store_document(&writer.into_vec()).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(1));
        let text = reader.string().unwrap();
        assert!(text.contains("(2 FILE(S))"));
        assert!(text.contains("---- runtime-1.log ----\nbody"));
        assert!(text.contains("(无法读取该文件)"));
        assert!(text.ends_with("---- 系统 crash 缓冲区 ----\ncrash block"));
        assert!(reader.finish());
    }

    #[test]
    fn the_capture_plan_carries_the_commands_and_the_cadence() {
        let plan = capture_plan(4242);
        let mut reader = Reader::new(&plan);
        assert_eq!(reader.i64(), Some(1_000));
        assert_eq!(reader.u32(), Some(2));
        assert_eq!(reader.u32(), Some(5));
        for expected in ["logcat", "-v", "time", "--pid", "4242"] {
            assert_eq!(reader.string().as_deref(), Some(expected));
        }
        assert_eq!(reader.u32(), Some(3));
        for expected in ["logcat", "-v", "time"] {
            assert_eq!(reader.string().as_deref(), Some(expected));
        }
        assert!(reader.finish());
    }

    #[test]
    fn one_line_answers_the_budget_and_the_rotation() {
        let session = Session::new();
        let mut writer = Writer::new();
        writer.string("hello");
        let line = capture_line(&session, &writer.into_vec()).unwrap();
        let mut reader = Reader::new(&line);
        assert_eq!(reader.i64(), Some(6));
        assert_eq!(reader.u8(), Some(0));
        assert!(reader.finish());
        assert_eq!(session.written(), 6);

        // A line that pushes the counter over the cap asks for a new file.
        let filler = "x".repeat((store::MAX_FILE_BYTES - 8) as usize);
        let mut writer = Writer::new();
        writer.string(&filler);
        let line = capture_line(&session, &writer.into_vec()).unwrap();
        let mut reader = Reader::new(&line);
        assert_eq!(reader.i64(), Some(store::MAX_FILE_BYTES - 1));
        assert_eq!(reader.u8(), Some(0));
        let mut writer = Writer::new();
        writer.string("y");
        let line = capture_line(&session, &writer.into_vec()).unwrap();
        let mut reader = Reader::new(&line);
        assert_eq!(reader.i64(), Some(store::MAX_FILE_BYTES + 1));
        assert_eq!(reader.u8(), Some(1));
    }

    #[test]
    fn the_mirror_payload_pins_the_two_columns() {
        let layout = mirror_layout();
        let mut reader = Reader::new(&layout);
        assert_eq!(reader.i64(), Some(200));
        assert_eq!(reader.i64(), Some(5_000));
        assert_eq!(reader.i64(), Some(10_000));
        assert!(reader.finish());

        let mut writer = Writer::new();
        writer.u32(1);
        writer.string("key");
        writer.string("example.com");
        writer.i32(1);
        writer.i32(1);
        writer.i64(1_000);
        writer.i64(301_000);
        writer.i64(2_000);
        writer.i64(7);
        writer.i64(300);
        writer.i32(45);
        let rows = mirror_rows(&writer.into_vec()).unwrap();
        let mut outer = Reader::new(&rows);
        assert_eq!(outer.u32(), Some(1));
        let mut reader = Reader::new(outer.blob().unwrap());
        assert_eq!(reader.string().as_deref(), Some("key"));
        assert_eq!(reader.string().as_deref(), Some("example.com"));
        assert_eq!(reader.i32(), Some(1));
        assert_eq!(reader.i32(), Some(1));
        assert_eq!(reader.i64(), Some(1_000));
        assert_eq!(reader.i64(), Some(301_000));
        assert_eq!(reader.i64(), Some(2_000));
        assert_eq!(reader.i64(), Some(7));
        assert_eq!(reader.i64(), Some(300));
        assert_eq!(reader.string().as_deref(), Some(""));
        assert_eq!(reader.blob(), Some(&[][..]));
        assert_eq!(reader.i32(), Some(45));
        assert!(reader.finish());
        assert!(outer.finish());
    }

    #[test]
    fn drift_is_a_failed_decode() {
        assert_eq!(store_index(&[0, 0, 0, 1]), None);
        assert_eq!(store_document(&[0, 0, 0, 1]), None);
        assert_eq!(mirror_rows(&[0, 0, 0, 1]), None);
        // An unknown presence byte on a section is drift too.
        let mut writer = Writer::new();
        writer.u32(1);
        writer.string("runtime.log");
        writer.u8(2);
        writer.string("stamp");
        assert_eq!(store_document(&writer.into_vec()), None);
    }
}
