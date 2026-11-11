use super::*;
use crate::engine::Plan;

#[test]
fn entries_round_trip() {
    let list = vec![
        ("ipv4 1.1.1.1".to_string(), 1.5),
        ("名字".to_string(), 0.25),
        (String::new(), 2.0),
    ];
    let encoded = encode_plan_entries(&list);
    assert_eq!(decode_plan_entries(&encoded), Some(list));
}

#[test]
fn an_empty_entry_list_is_valid() {
    let encoded = encode_plan_entries(&[]);
    assert_eq!(decode_plan_entries(&encoded), Some(Vec::new()));
}

#[test]
fn a_drifted_version_is_rejected() {
    let mut encoded = encode_plan_entries(&[("a".to_string(), 1.0)]);
    encoded[0] = LAYOUT_VERSION + 1;
    assert_eq!(decode_plan_entries(&encoded), None);
}

#[test]
fn a_truncated_payload_is_rejected() {
    let encoded = encode_plan_entries(&[("abc".to_string(), 1.0)]);
    for cut in 0..encoded.len() {
        assert_eq!(
            decode_plan_entries(&encoded[..cut]),
            None,
            "cut at {cut} must be rejected"
        );
    }
}

#[test]
fn trailing_bytes_are_rejected() {
    let mut encoded = encode_plan_entries(&[("a".to_string(), 1.0)]);
    encoded.push(0);
    assert_eq!(decode_plan_entries(&encoded), None);
}

#[test]
fn a_count_beyond_the_payload_is_rejected() {
    let mut encoded = encode_plan_entries(&[]);
    encoded[1..5].copy_from_slice(&1u32.to_le_bytes());
    assert_eq!(decode_plan_entries(&encoded), None);
}

#[test]
fn invalid_utf8_in_an_id_is_rejected() {
    let mut encoded = encode_plan_entries(&[("ab".to_string(), 1.0)]);
    // The id starts after the layout (1) + count (4) + id_len (4), so at byte 9.
    encoded[9] = 0xff;
    assert_eq!(decode_plan_entries(&encoded), None);
}

#[test]
fn plan_encoding_carries_the_indices_and_the_flag() {
    let plan = Plan {
        primary: Some(2),
        fallbacks: vec![0, 1],
        exploration: true,
    };
    let encoded = encode_plan(&plan);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(i32::from_le_bytes(encoded[1..5].try_into().unwrap()), 2);
    assert_eq!(encoded[5], 1);
    assert_eq!(u32::from_le_bytes(encoded[6..10].try_into().unwrap()), 2);
    assert_eq!(u32::from_le_bytes(encoded[10..14].try_into().unwrap()), 0);
    assert_eq!(u32::from_le_bytes(encoded[14..18].try_into().unwrap()), 1);

    let empty = encode_plan(&Plan::default());
    assert_eq!(i32::from_le_bytes(empty[1..5].try_into().unwrap()), -1);
    assert_eq!(empty[5], 0);
    assert_eq!(u32::from_le_bytes(empty[6..10].try_into().unwrap()), 0);
    assert_eq!(empty.len(), 10);
}

#[test]
fn score_encoding_is_the_documented_17_bytes() {
    let encoded = encode_score(1.25, true, 7.5);
    assert_eq!(encoded.len(), SCORE_BYTES);
    assert_eq!(f64::from_le_bytes(encoded[..8].try_into().unwrap()), 1.25);
    assert_eq!(encoded[8], 1);
    assert_eq!(f64::from_le_bytes(encoded[9..].try_into().unwrap()), 7.5);
}
