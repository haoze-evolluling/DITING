use super::*;
use crate::tuning::TUNING;

#[test]
fn a_target_round_trips() {
    let payload = encode_target("dns.google", "853");
    assert_eq!(payload[0], LAYOUT_VERSION);
    assert_eq!(
        decode_target(&payload),
        Some(("dns.google".to_string(), "853".to_string()))
    );
    assert_eq!(
        decode_target(&encode_target("", "")),
        Some((String::new(), String::new()))
    );
    assert_eq!(
        decode_target(&encode_target("2001:db8::1", "53")),
        Some(("2001:db8::1".to_string(), "53".to_string()))
    );
}

#[test]
fn an_address_round_trips() {
    let payload = encode_address("[2001:db8::1]:853");
    assert_eq!(
        decode_address(&payload),
        Some("[2001:db8::1]:853".to_string())
    );
}

#[test]
fn the_tuning_table_round_trips() {
    let payload = encode_tuning(&TUNING);
    assert_eq!(payload.len(), 1 + TUNING_FIELDS * 8);
    assert_eq!(decode_tuning(&payload), Some(TUNING));
}

#[test]
fn ids_round_trip() {
    let payload = encode_ids(&[1, u64::MAX, 42]);
    assert_eq!(decode_ids(&payload), Some(vec![1, u64::MAX, 42]));
    assert_eq!(decode_ids(&encode_ids(&[])), Some(Vec::new()));
}

#[test]
fn a_bad_version_length_or_trailing_byte_is_rejected() {
    let mut drifted = encode_target("dns.google", "53");
    drifted[0] = LAYOUT_VERSION + 1;
    assert_eq!(decode_target(&drifted), None);

    let mut truncated = encode_target("dns.google", "53");
    truncated.pop();
    assert_eq!(decode_target(&truncated), None);

    let mut trailing = encode_target("dns.google", "53");
    trailing.push(0);
    assert_eq!(decode_target(&trailing), None);

    assert_eq!(decode_target(&[]), None);
    assert_eq!(decode_ids(&[]), None);
    // A declared id count that cannot fit is rejected before allocating.
    let mut huge = vec![LAYOUT_VERSION, 0xFF, 0xFF, 0xFF, 0xFF];
    huge.push(0);
    assert_eq!(decode_ids(&huge), None);
}
