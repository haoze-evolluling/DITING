//! Replays the LRU trace produced by the old Go `ipDomainCache`.
//!
//! The script covers in-place updates, `get` not promoting, eviction of the least-recently-written
//! entry (not the least-recently-read one), re-putting the same value as a touch, and empty keys
//! being ignored. The fixture was generated with a capacity of 3.

use diting_ipcache_core::IpDomainCache;

const TRACE: &str = include_str!("fixtures/lru_trace.tsv");

#[test]
fn the_lru_trace_replays_exactly() {
    let cache = IpDomainCache::new(3);
    let mut rows = 0;
    for line in TRACE.lines().skip(1) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 5, "row shape: {line}");
        let expected_size: u32 = fields[4].parse().unwrap();
        if fields[0] == "put" {
            cache.put(fields[1], fields[2]);
        } else {
            let actual = cache.get(fields[1]).unwrap_or_default();
            assert_eq!(actual, fields[3], "row {line}: domain");
        }
        assert_eq!(cache.len(), expected_size, "row {line}: size");
        rows += 1;
    }
    assert_eq!(rows, 25, "the fixture is the 25-step trace");
}
