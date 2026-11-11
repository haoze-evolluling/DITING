//! Replays the three traces produced by the old Go implementations.
//!
//! * `logagg_trace.tsv` — `log_aggregator.go`: FIFO drains, the 50-row flush threshold, the
//!   2048-slot capacity drop and the 3/4 high-water shedding of unblocked connection rows (with both
//!   counters). The generator pushed into the channel and pulled from it directly, so the rows are
//!   exactly what the old aggregate loop would have batched.
//! * `traffic_trace.tsv` — `traffic_tracker.go`: the `uid <= 0` / non-positive gate, the delta swap
//!   and the totals that survive it, plus the interval normalization (`SetTickInterval(0)` is a
//!   no-op).
//! * `uidcache_trace.tsv` — `uid_cache.go` driven through `resolveFlowUID` / `PackageForUid` with an
//!   injected clock: positive and negative TTLs, the 4-byte vs 16-byte address widths, `uint16` /
//!   `uint8` key truncation, prune-then-reset at 1024 and the 256-entry package reset.

use diting_telemetry_core::logagg::{BATCH_SIZE, HIGH_WATER_MARK};
use diting_telemetry_core::uidcache::Addr;
use diting_telemetry_core::{
    Delta, FlowKey, FlowUidCache, LogAggregator, LogItem, PushOutcome, TrafficTracker,
    UidPackageCache,
};

const LOGAGG: &str = include_str!("fixtures/logagg_trace.tsv");
const TRAFFIC: &str = include_str!("fixtures/traffic_trace.tsv");
const UIDCACHE: &str = include_str!("fixtures/uidcache_trace.tsv");

fn rows(fixture: &str) -> impl Iterator<Item = Vec<&str>> {
    fixture
        .lines()
        .skip(1)
        .filter(|line| !line.is_empty())
        .map(|line| line.split('\t').collect())
}

fn item(domain: &str, blocked: bool, blocked_by: &str) -> LogItem {
    LogItem {
        domain: domain.to_string(),
        blocked,
        query_type: 0,
        response_time_ms: 0,
        app_name: String::new(),
        resolved_ips: String::new(),
        blocked_by: blocked_by.to_string(),
        error_message: String::new(),
        cached: false,
        timestamp_ms: 0,
        ttl: 0,
    }
}

#[test]
fn the_log_aggregator_trace_replays_exactly() {
    let aggregator = LogAggregator::new();
    // The fixture pushes far past the high-water mark, so the constants are part of the replay.
    assert_eq!(HIGH_WATER_MARK, 1536);

    for fields in rows(LOGAGG) {
        assert_eq!(fields.len(), 8, "row shape: {fields:?}");
        let expected_pending: usize = fields[5].parse().unwrap();
        let expected_dropped: u64 = fields[6].parse().unwrap();
        let expected_conn: u64 = fields[7].parse().unwrap();

        match fields[0] {
            "push" => {
                let before = aggregator.pending();
                let outcome = aggregator.push(item(fields[4], fields[2] == "true", fields[3]));
                let after = aggregator.pending();
                let expected_outcome = if after == before {
                    PushOutcome::Dropped
                } else if after >= BATCH_SIZE {
                    PushOutcome::Full
                } else {
                    PushOutcome::Buffered
                };
                assert_eq!(outcome, expected_outcome, "row {fields:?}");
            }
            "push_many" => {
                let count: usize = fields[1].parse().unwrap();
                for index in 0..count {
                    aggregator.push(item(
                        &format!("d{index}.example"),
                        fields[2] == "true",
                        fields[3],
                    ));
                }
            }
            "drain" => {
                let max: usize = fields[1].parse().unwrap();
                let expected: Vec<&str> = if fields[4].is_empty() {
                    Vec::new()
                } else {
                    fields[4].split(',').collect()
                };
                let (drained, remaining) = aggregator.drain(max);
                assert_eq!(
                    drained
                        .iter()
                        .map(|row| row.domain.as_str())
                        .collect::<Vec<_>>(),
                    expected,
                    "row {fields:?}"
                );
                assert_eq!(remaining, expected_pending, "row {fields:?}: remaining");
            }
            other => panic!("unknown row {other}"),
        }

        assert_eq!(aggregator.pending(), expected_pending, "row {fields:?}");
        assert_eq!(aggregator.dropped(), expected_dropped, "row {fields:?}");
        assert_eq!(aggregator.dropped_conn(), expected_conn, "row {fields:?}");
    }
}

fn delta_text(deltas: &[Delta]) -> String {
    let mut sorted = deltas.to_vec();
    sorted.sort_by_key(|delta| delta.uid);
    sorted
        .iter()
        .map(|delta| format!("{}:{}:{}", delta.uid, delta.tx, delta.rx))
        .collect::<Vec<_>>()
        .join(",")
}

#[test]
fn the_traffic_trace_replays_exactly() {
    let tracker = TrafficTracker::new();

    for fields in rows(TRAFFIC) {
        assert_eq!(fields.len(), 5, "row shape: {fields:?}");
        match fields[0] {
            "record" => {
                tracker.record(
                    fields[1].parse().unwrap(),
                    fields[2].parse().unwrap(),
                    fields[3].parse().unwrap(),
                );
            }
            "tick" => {
                assert_eq!(delta_text(&tracker.tick()), fields[4], "row {fields:?}");
            }
            "totals" => {
                let uid: i32 = fields[1].parse().unwrap();
                let (tx, rx) = tracker.totals(uid).expect("known uid");
                assert_eq!(format!("{tx}:{rx}"), fields[4], "row {fields:?}");
            }
            "set_interval" => {
                tracker.set_interval_ms(fields[1].parse().unwrap());
                assert_eq!(
                    tracker.interval_ms().to_string(),
                    fields[4],
                    "row {fields:?}"
                );
            }
            "interval" => assert_eq!(
                tracker.interval_ms().to_string(),
                fields[4],
                "row {fields:?}"
            ),
            other => panic!("unknown row {other}"),
        }
    }
}

/// `4:10.0.0.2` / `16:2001:db8::1`, and the 16-byte IPv4-mapped form Go's `net.ParseIP` produces.
fn parse_addr(field: &str) -> Addr {
    let (width, text) = field.split_once(':').expect("width prefix");
    match width {
        "4" => Addr::V4(text.parse::<std::net::Ipv4Addr>().unwrap().octets()),
        "16" => match text.parse::<std::net::Ipv6Addr>() {
            Ok(ip) => Addr::V6(ip.octets()),
            Err(_) => {
                let v4 = text.parse::<std::net::Ipv4Addr>().unwrap().octets();
                let mut bytes = [0u8; 16];
                bytes[10] = 0xff;
                bytes[11] = 0xff;
                bytes[12..].copy_from_slice(&v4);
                Addr::V6(bytes)
            }
        },
        other => panic!("unknown address width {other}"),
    }
}

/// One `resolveFlow` pass: a hit answers, a miss asks the inner resolver and stores its answer.
fn resolve_flow(cache: &mut FlowUidCache, key: FlowKey, now_ns: i64, inner: i32) -> i32 {
    match cache.lookup(&key, now_ns) {
        Some(uid) => uid,
        None => {
            cache.store(key, inner, now_ns);
            inner
        }
    }
}

#[test]
fn the_uid_cache_trace_replays_exactly() {
    let mut flows = FlowUidCache::new();
    let packages = UidPackageCache::new();

    for fields in rows(UIDCACHE) {
        assert_eq!(fields.len(), 12, "row shape: {fields:?}");
        let now_ns: i64 = fields[8].parse().unwrap();
        let expected_len: u32 = fields[11].parse().unwrap();
        match (fields[0], fields[1]) {
            ("flow", "lookup") => {
                let key = FlowKey::new(
                    parse_addr(fields[2]),
                    fields[3].parse().unwrap(),
                    parse_addr(fields[4]),
                    fields[5].parse().unwrap(),
                    fields[6].parse().unwrap(),
                );
                let inner: i32 = fields[9].parse().unwrap();
                let result = resolve_flow(&mut flows, key, now_ns, inner);
                assert_eq!(result.to_string(), fields[10], "row {fields:?}");
                assert_eq!(flows.len(), expected_len, "row {fields:?}");
            }
            ("flow", "fill") => {
                let count: i32 = fields[7].parse().unwrap();
                let inner: i32 = fields[9].parse().unwrap();
                for port in 0..count {
                    let key = FlowKey::new(
                        Addr::V4([10, 0, 0, 2]),
                        port,
                        Addr::V4([1, 1, 1, 1]),
                        443,
                        6,
                    );
                    resolve_flow(&mut flows, key, now_ns, inner);
                }
                assert_eq!(flows.len(), expected_len, "row {fields:?}");
            }
            ("flow", "len") => assert_eq!(flows.len(), expected_len, "row {fields:?}"),
            ("package", "lookup") => {
                let uid: i32 = fields[7].parse().unwrap();
                let inner = fields[9];
                let result = match packages.lookup(uid, now_ns) {
                    Some(name) => name,
                    None => {
                        if !inner.is_empty() {
                            packages.store(uid, inner, now_ns);
                        }
                        inner.to_string()
                    }
                };
                assert_eq!(result, fields[10], "row {fields:?}");
                assert_eq!(packages.len(), expected_len, "row {fields:?}");
            }
            ("package", "len") => assert_eq!(packages.len(), expected_len, "row {fields:?}"),
            other => panic!("unknown row {other:?}"),
        }
    }
}
