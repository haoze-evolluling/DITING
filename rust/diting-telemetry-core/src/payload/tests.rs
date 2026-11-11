use super::*;
use crate::logagg::LogItem;
use crate::traffic::Delta;
use crate::uidcache::{Addr, FlowKey};

fn sample() -> LogItem {
    LogItem {
        domain: "ads.example.com".to_string(),
        blocked: true,
        query_type: 28,
        response_time_ms: 42,
        app_name: "com.example.app".to_string(),
        resolved_ips: "1.2.3.4,::1".to_string(),
        blocked_by: "blocklist".to_string(),
        error_message: String::new(),
        cached: true,
        timestamp_ms: 1_700_000_000_000,
        ttl: 0,
    }
}

#[test]
fn a_log_row_round_trips() {
    let encoded = encode_log_push(&sample());
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(decode_log_push(&encoded), Some(sample()));

    let batch = encode_log_batch(&[
        sample(),
        sample(),
        LogItem {
            ttl: -1,
            ..sample()
        },
    ]);
    let decoded = decode_log_batch(&batch).expect("batch");
    assert_eq!(decoded.len(), 3);
    assert_eq!(decoded[0], sample());
    assert_eq!(decoded[2].ttl, -1);
}

#[test]
fn an_empty_batch_is_still_a_valid_payload() {
    let batch = encode_log_batch(&[]);
    assert_eq!(decode_log_batch(&batch), Some(Vec::new()));
}

#[test]
fn a_bad_version_or_length_is_rejected() {
    let mut drifted = encode_log_push(&sample());
    drifted[0] = LAYOUT_VERSION + 1;
    assert!(decode_log_push(&drifted).is_none());

    let mut truncated = encode_log_push(&sample());
    truncated.pop();
    assert!(decode_log_push(&truncated).is_none());

    let mut trailing = encode_log_push(&sample());
    trailing.push(0);
    assert!(decode_log_push(&trailing).is_none());

    assert!(decode_log_push(&[]).is_none());
}

#[test]
fn invalid_utf8_is_replaced_not_rejected() {
    // A domain with a raw 0xFF byte: Go's json.Marshal would have replaced it with U+FFFD anyway.
    let mut payload = vec![LAYOUT_VERSION, 0, 0];
    payload.extend_from_slice(&0i32.to_le_bytes());
    payload.extend_from_slice(&0i64.to_le_bytes());
    payload.extend_from_slice(&0i64.to_le_bytes());
    payload.extend_from_slice(&0i64.to_le_bytes());
    payload.extend_from_slice(&2u32.to_le_bytes());
    payload.extend_from_slice(&[b'a', 0xFF]);
    for _ in 0..3 {
        payload.extend_from_slice(&0u32.to_le_bytes());
    }
    payload.extend_from_slice(&1u32.to_le_bytes());
    payload.extend_from_slice(&[0xFF]);
    let item = decode_log_push(&payload).expect("lossy decode");
    assert_eq!(item.domain, "a\u{FFFD}");
    assert_eq!(item.error_message, "\u{FFFD}");
}

#[test]
fn a_tick_round_trips() {
    let deltas = vec![
        Delta {
            uid: 1000,
            tx: 1,
            rx: 2,
        },
        Delta {
            uid: 10_123,
            tx: u64::MAX,
            rx: 0,
        },
    ];
    let encoded = encode_traffic_tick(&deltas);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(decode_traffic_tick(&encoded), Some(deltas));

    let empty = encode_traffic_tick(&[]);
    assert_eq!(decode_traffic_tick(&empty), Some(Vec::new()));
}

#[test]
fn a_flow_key_round_trips_for_both_address_widths() {
    let key = FlowKey::new(
        Addr::V4([10, 0, 0, 2]),
        40_000,
        Addr::V6([0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
        53,
        17,
    );
    let lookup = encode_flow_key(&key, 1234, None);
    assert_eq!(decode_flow_lookup(&lookup), Some((key, 1234)));

    let store = encode_flow_key(&key, 1234, Some(10_123));
    assert_eq!(decode_flow_store(&store), Some((key, 1234, 10_123)));
    // The lookup decoder refuses the store payload (it has one extra field).
    assert_eq!(decode_flow_lookup(&store), None);
}

#[test]
fn a_flow_key_with_a_bad_address_length_is_rejected() {
    let mut payload = vec![LAYOUT_VERSION, 3, 1, 2, 3];
    payload.extend_from_slice(&[0u8; 4]);
    payload.extend_from_slice(&0i32.to_le_bytes());
    payload.extend_from_slice(&0i32.to_le_bytes());
    payload.extend_from_slice(&0i32.to_le_bytes());
    payload.extend_from_slice(&0i64.to_le_bytes());
    assert_eq!(decode_flow_lookup(&payload), None);
}
