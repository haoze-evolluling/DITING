//! Replays the transport fixtures produced by the old Go implementation.
//!
//! * `truncation.tsv` — `isTruncatedResponse` itself (every flags byte, short buffers, nil).
//! * `targets.tsv` — the `net.SplitHostPort` + default-port expression both resolvers opened with,
//!   run through Go's own splitter.
//! * `tcp_frame.tsv` — `queryPlainTCPContext` against a capture server: the exact request bytes it
//!   wrote and the response it accepted.
//! * `dot_frame.tsv` — `executeDoTQuery` against a real (self-signed) DoT server: request framing and
//!   the response-length validity rules, including `0`, `4096`, `4097` and `65535`.
//! * `doh_status.tsv` — `queryDoHContext` against `httptest` servers: the status classification and
//!   the 65535-byte body cap.
//! * `pool_trace.tsv` — the old `popIdleDoTConn` / `putIdleDoTConn` / `closeDoTConns` driven with
//!   scripted connections and a scripted clock (the `lastUsed` stamps are rewritten per row).
//! * `retry_plan.tsv` — the inline plain-UDP deadline expressions, copied verbatim into the
//!   generator because the Go side has no callable function for them.
//! * `doq_skip.tsv` — the inline DoQ prefix-strip expression, same reasoning.

use diting_upstream_core::doh::{should_retry, status_kind, StatusKind};
use diting_upstream_core::endpoint::{split_target, TargetProtocol};
use diting_upstream_core::framing::{
    doq_skip, dot_response_length, encode_length_prefixed, first_deadline_ns, is_truncated,
    retry_deadline_ns, tcp_response_length, DotLength,
};
use diting_upstream_core::plan::{is_policy_rejection, strategy, Strategy};
use diting_upstream_core::pool::{Acquired, DotPool};
use diting_upstream_core::tuning::TUNING;

const TRUNCATION: &str = include_str!("fixtures/truncation.tsv");
const TARGETS: &str = include_str!("fixtures/targets.tsv");
const TCP_FRAME: &str = include_str!("fixtures/tcp_frame.tsv");
const DOT_FRAME: &str = include_str!("fixtures/dot_frame.tsv");
const DOH_STATUS: &str = include_str!("fixtures/doh_status.tsv");
const POOL_TRACE: &str = include_str!("fixtures/pool_trace.tsv");
const RETRY_PLAN: &str = include_str!("fixtures/retry_plan.tsv");
const DOQ_SKIP: &str = include_str!("fixtures/doq_skip.tsv");

fn rows(fixture: &str) -> impl Iterator<Item = Vec<&str>> {
    fixture
        .lines()
        .skip(1)
        .filter(|line| !line.is_empty())
        .map(|line| line.split('\t').collect())
}

fn bytes(hex: &str) -> Vec<u8> {
    if hex.is_empty() {
        return Vec::new();
    }
    assert_eq!(hex.len() % 2, 0, "hex {hex}");
    (0..hex.len() / 2)
        .map(|index| u8::from_str_radix(&hex[index * 2..index * 2 + 2], 16).expect("hex"))
        .collect()
}

fn join_ids(ids: &[u64]) -> String {
    ids.iter().map(u64::to_string).collect::<Vec<_>>().join(",")
}

#[test]
fn the_truncation_corpus_replays_exactly() {
    let mut count = 0;
    for fields in rows(TRUNCATION) {
        assert_eq!(fields.len(), 2, "row shape: {fields:?}");
        assert_eq!(
            is_truncated(&bytes(fields[0])),
            fields[1] == "true",
            "row {fields:?}"
        );
        count += 1;
    }
    assert_eq!(count, 259);
}

#[test]
fn the_target_corpus_replays_exactly() {
    let mut count = 0;
    for fields in rows(TARGETS) {
        assert_eq!(fields.len(), 4, "row shape: {fields:?}");
        let protocol = match fields[0] {
            "PLAIN" => TargetProtocol::Plain,
            "DOT" => TargetProtocol::Dot,
            other => panic!("unknown protocol {other}"),
        };
        assert_eq!(
            split_target(fields[1], protocol),
            (fields[2].to_string(), fields[3].to_string()),
            "row {fields:?}"
        );
        count += 1;
    }
    assert_eq!(count, 36);
}

#[test]
fn the_tcp_frame_corpus_replays_exactly() {
    let mut count = 0;
    for fields in rows(TCP_FRAME) {
        assert_eq!(fields.len(), 5, "row shape: {fields:?}");
        let query = bytes(fields[0]);
        let response = bytes(fields[1]);
        let request = bytes(fields[2]);
        assert_eq!(fields[4], "ok", "row {fields:?}");
        assert_eq!(encode_length_prefixed(&query), request, "row {fields:?}");
        let header = (response.len() as u16).to_be_bytes();
        assert_eq!(
            tcp_response_length(&header),
            Some(response.len()),
            "row {fields:?}"
        );
        assert_eq!(bytes(fields[3]), response, "row {fields:?}");
        count += 1;
    }
    assert_eq!(count, 5);
}

#[test]
fn the_dot_frame_corpus_replays_exactly() {
    let mut count = 0;
    for fields in rows(DOT_FRAME) {
        assert_eq!(fields.len(), 5, "row shape: {fields:?}");
        let query = bytes(fields[0]);
        let declared: u16 = fields[1].parse().unwrap();
        let body_len: usize = fields[2].parse().unwrap();
        assert_eq!(
            encode_length_prefixed(&query),
            bytes(fields[3]),
            "row {fields:?}"
        );
        let expected = if fields[4] == "error" {
            DotLength::Invalid(declared as usize)
        } else {
            DotLength::Valid(declared as usize)
        };
        assert_eq!(
            dot_response_length(&declared.to_be_bytes()),
            Some(expected),
            "row {fields:?}"
        );
        if expected == DotLength::Valid(declared as usize) {
            assert_eq!(body_len, declared as usize, "row {fields:?}");
        }
        count += 1;
    }
    assert_eq!(count, 6);
}

#[test]
fn the_doh_status_corpus_replays_exactly() {
    let mut count = 0;
    for fields in rows(DOH_STATUS) {
        assert_eq!(fields.len(), 4, "row shape: {fields:?}");
        let status: i32 = fields[0].parse().unwrap();
        let body_len: usize = fields[1].parse().unwrap();
        let result_len: usize = fields[3].parse().unwrap();
        let expected = match fields[2] {
            "ok" => StatusKind::Ok,
            "DoH rate limited (403)" => StatusKind::RateLimited,
            text if text.starts_with("DoH status ") => StatusKind::Other,
            other => panic!("unknown outcome {other}"),
        };
        assert_eq!(status_kind(status), expected, "row {fields:?}");
        // The body is only read on 200, and then capped by `io.LimitReader(resp.Body, maxReadBytes)`.
        if expected == StatusKind::Ok {
            assert_eq!(
                result_len,
                body_len.min(TUNING.max_read_bytes as usize),
                "row {fields:?}"
            );
        }
        if expected == StatusKind::RateLimited {
            assert_eq!(status, 403);
        }
        count += 1;
    }
    assert_eq!(count, 7);
}

#[test]
fn the_pool_trace_replays_exactly() {
    let pool = DotPool::new();
    let mut count = 0;
    for fields in rows(POOL_TRACE) {
        assert_eq!(fields.len(), 6, "row shape: {fields:?}");
        let host = fields[1];
        let now_ms: i64 = fields[2].parse().unwrap();
        match fields[0] {
            "put" => {
                let id: u64 = fields[3].parse().unwrap();
                let kept = pool.release(host, id, now_ms);
                assert_eq!(kept, fields[4] == "kept", "row {fields:?}: release verdict");
                assert!(fields[5].is_empty(), "row {fields:?}");
            }
            "acquire" => {
                let mut reused = None;
                let mut expired = Vec::new();
                loop {
                    match pool.acquire(host, now_ms) {
                        None => break,
                        Some(Acquired::Expired(id)) => expired.push(id),
                        Some(Acquired::Idle(id)) => {
                            reused = Some(id);
                            break;
                        }
                    }
                }
                expired.sort_unstable();
                assert_eq!(
                    reused.map_or_else(String::new, |id| id.to_string()),
                    fields[4],
                    "row {fields:?}: reused"
                );
                assert_eq!(join_ids(&expired), fields[5], "row {fields:?}: expired");
            }
            "close_all" => {
                let mut ids = pool.close_all();
                ids.sort_unstable();
                assert_eq!(join_ids(&ids), fields[5], "row {fields:?}: closed");
            }
            other => panic!("unknown op {other}"),
        }
        count += 1;
    }
    assert_eq!(count, 18);
}

#[test]
fn the_retry_plan_corpus_replays_exactly() {
    let mut count = 0;
    for fields in rows(RETRY_PLAN) {
        assert_eq!(fields.len(), 7, "row shape: {fields:?}");
        let now_ns: i64 = fields[1].parse().unwrap();
        let initial_ns: i64 = fields[2].parse().unwrap();
        let deadline_ns: i64 = fields[3].parse().unwrap();
        let retry_index: u32 = fields[4].parse().unwrap();
        let expected: i64 = fields[5 + 1].parse().unwrap();
        match fields[0] {
            "first" => {
                assert_eq!(
                    first_deadline_ns(now_ns, initial_ns, deadline_ns),
                    expected,
                    "row {fields:?}"
                );
            }
            "retry" => {
                let want = if fields[5] == "1" {
                    Some(expected)
                } else {
                    None
                };
                assert_eq!(
                    retry_deadline_ns(now_ns, initial_ns, deadline_ns, retry_index),
                    want,
                    "row {fields:?}"
                );
            }
            other => panic!("unknown op {other}"),
        }
        count += 1;
    }
    assert_eq!(count, 80);
}

#[test]
fn the_doq_skip_corpus_replays_exactly() {
    let mut count = 0;
    for fields in rows(DOQ_SKIP) {
        assert_eq!(fields.len(), 2, "row shape: {fields:?}");
        let raw = bytes(fields[0]);
        let expected: usize = fields[1].parse().unwrap();
        assert_eq!(doq_skip(&raw), expected, "row {fields:?}");
        count += 1;
    }
    assert_eq!(count, 11);
}

/// The two tables that have no fixture of their own.
#[test]
fn the_mode_and_rcode_tables_are_pinned() {
    assert_eq!(strategy("single"), Strategy::Single);
    assert_eq!(strategy("primary_backup"), Strategy::PrimaryBackup);
    assert_eq!(strategy("race"), Strategy::ParallelRace);
    assert_eq!(strategy("prediction"), Strategy::SmartPrediction);
    assert_eq!(strategy("something"), Strategy::Single);
    assert!(is_policy_rejection(5) && is_policy_rejection(1) && is_policy_rejection(4));
    assert!(!is_policy_rejection(3) && !is_policy_rejection(2));
}

/// `should_retry` is not in a fixture either: `queryDoHContext`'s retry is only reachable when the
/// HTTP/2 connection dies mid-flight.
#[test]
fn the_doh_retry_rule_is_pinned() {
    assert!(should_retry(1, "Post \"https://x\": EOF"));
    assert!(!should_retry(2, "EOF"));
    assert!(!should_retry(1, "connection reset by peer"));
}
