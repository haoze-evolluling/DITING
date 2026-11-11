//! Replays the key corpus and the dedupe trace produced by the old Go implementation.
//!
//! `keys.tsv` pins `connLogKey` byte for byte (empty fields, unicode, `|` inside a field, negative
//! numbers). `dedup_trace.tsv` pins the set semantics: first sighting new, repeat duplicate, the
//! blocked prefix/reason being part of the key, and a reset dropping the entries while keeping the
//! overflow counter.

use diting_connlog_core::{build_key, ConnLogDedup};

const KEYS: &str = include_str!("fixtures/keys.tsv");
const TRACE: &str = include_str!("fixtures/dedup_trace.tsv");

#[test]
fn the_key_corpus_matches_the_old_builder() {
    let mut rows = 0;
    for line in KEYS.lines().skip(1) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 7, "row shape: {line}");
        let port: i32 = fields[3].parse().unwrap();
        let protocol: i32 = fields[4].parse().unwrap();
        assert_eq!(
            build_key(fields[0], fields[1], fields[2], port, protocol, fields[5]),
            fields[6],
            "row {line}"
        );
        rows += 1;
    }
    assert_eq!(rows, 7);
}

#[test]
fn the_dedupe_trace_replays_exactly() {
    let dedup = ConnLogDedup::new();
    let mut rows = 0;
    for line in TRACE.lines().skip(1) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 10, "row shape: {line}");
        let expected_size: u32 = fields[8].parse().unwrap();
        let expected_cleared: u64 = fields[9].parse().unwrap();

        if fields[0] == "reset" {
            dedup.reset();
        } else {
            let port: i32 = fields[4].parse().unwrap();
            let protocol: i32 = fields[5].parse().unwrap();
            let duplicate = dedup.mark(fields[1], fields[2], fields[3], port, protocol, fields[6]);
            assert_eq!(duplicate, fields[7] == "true", "row {line}: duplicate flag");
        }
        assert_eq!(dedup.size(), expected_size, "row {line}: size");
        assert_eq!(dedup.cleared(), expected_cleared, "row {line}: cleared");
        rows += 1;
    }
    assert_eq!(rows, 7);
}
