//! Layout round trips and rejections: the Go decoder and this encoder have to agree byte for byte.

use super::*;
use crate::engine::PARENTAL_CONTROL_SUFFIX;
use crate::hash::HASH_SIZE;

fn encode_apply(service: u8, queried: &[HostnameHash], received: &[&str]) -> Vec<u8> {
    let mut out = Vec::new();
    out.push(LAYOUT_VERSION);
    out.push(service);
    out.push(queried.len() as u8);
    for hash in queried {
        out.extend_from_slice(hash);
    }
    out.extend_from_slice(&(received.len() as u16).to_le_bytes());
    for text in received {
        out.extend_from_slice(&(text.len() as u16).to_le_bytes());
        out.extend_from_slice(text.as_bytes());
    }
    out
}

fn sample_plan() -> Plan {
    Plan {
        empty: false,
        found: false,
        blocked: false,
        need_query: vec![[1u8; HASH_SIZE], [2u8; HASH_SIZE]],
        question: format!("0101.0202{PARENTAL_CONTROL_SUFFIX}"),
    }
}

#[test]
fn plan_round_trips() {
    let plan = sample_plan();
    assert_eq!(decode_plan(&encode_plan(&plan)), Ok(plan));
}

#[test]
fn plan_flags_round_trip() {
    for (empty, found, blocked) in [
        (true, true, false),
        (false, true, true),
        (false, false, true),
        (true, false, true),
    ] {
        let plan = Plan {
            empty,
            found,
            blocked,
            need_query: Vec::new(),
            question: String::new(),
        };
        let decoded = decode_plan(&encode_plan(&plan)).expect("round trip");
        assert_eq!(
            (decoded.empty, decoded.found, decoded.blocked),
            (empty, found, blocked)
        );
    }
}

#[test]
fn plan_layout_is_prefixed_with_the_version() {
    let encoded = encode_plan(&sample_plan());
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(encoded[1] & !0b111, 0, "only three flag bits are used");
    assert_eq!(encoded[2], 2, "two digests");
}

#[test]
fn apply_round_trips() {
    let queried = vec![[3u8; HASH_SIZE]];
    let encoded = encode_apply(1, &queried, &["abc", ""]);
    let decoded = decode_apply(&encoded).expect("round trip");
    assert_eq!(decoded.service, 1);
    assert_eq!(decoded.queried, queried);
    assert_eq!(decoded.received, vec!["abc".to_string(), String::new()]);
}

#[test]
fn wrong_layout_is_rejected() {
    let mut encoded = encode_plan(&sample_plan());
    encoded[0] = LAYOUT_VERSION + 1;
    assert!(decode_plan(&encoded).is_err());

    let mut request = encode_apply(0, &[], &[]);
    request[0] = LAYOUT_VERSION + 1;
    assert!(decode_apply(&request).is_err());
}

#[test]
fn trailing_bytes_are_rejected() {
    let mut encoded = encode_plan(&sample_plan());
    encoded.push(0);
    assert!(decode_plan(&encoded).is_err());

    let mut request = encode_apply(0, &[], &[]);
    request.push(0);
    assert!(decode_apply(&request).is_err());
}

#[test]
fn truncated_payloads_are_rejected() {
    let encoded = encode_plan(&sample_plan());
    for length in 0..encoded.len() {
        assert!(
            decode_plan(&encoded[..length]).is_err(),
            "prefix of {length} bytes should be rejected"
        );
    }

    let request = encode_apply(0, &[[1u8; HASH_SIZE]], &["abc"]);
    for length in 0..request.len() {
        assert!(
            decode_apply(&request[..length]).is_err(),
            "prefix of {length} bytes should be rejected"
        );
    }
}

#[test]
fn non_utf8_text_is_rejected() {
    let mut request = encode_apply(0, &[], &[]);
    // Empty the received list, then append one chunk of invalid UTF-8.
    request.truncate(3);
    request.extend_from_slice(&1u16.to_le_bytes());
    request.extend_from_slice(&1u16.to_le_bytes());
    request.push(0xff);
    assert!(decode_apply(&request).is_err());
}
