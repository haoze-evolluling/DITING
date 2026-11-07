use super::*;

#[test]
fn configure_round_trip_keeps_counts_and_raw_text() {
    let entries = vec![
        (
            10188,
            vec!["Example.COM.".to_string(), "  spaced  ".to_string()],
        ),
        (10200, Vec::new()),
        (-5, vec![String::new()]),
        (7, vec!["名字.example".to_string()]),
    ];
    let encoded = encode_configure(&entries);
    assert_eq!(decode_configure(&encoded), Some(entries));
}

#[test]
fn an_empty_configure_payload_is_valid() {
    let encoded = encode_configure(&[]);
    assert_eq!(decode_configure(&encoded), Some(Vec::new()));
}

#[test]
fn a_drifted_configure_version_is_rejected() {
    let mut encoded = encode_configure(&[(1, vec!["a".to_string()])]);
    encoded[0] = LAYOUT_VERSION + 1;
    assert_eq!(decode_configure(&encoded), None);
}

#[test]
fn a_truncated_configure_payload_is_rejected() {
    let encoded = encode_configure(&[(1, vec!["abc".to_string()]), (2, Vec::new())]);
    for cut in 0..encoded.len() {
        assert_eq!(decode_configure(&encoded[..cut]), None, "cut at {cut}");
    }
}

#[test]
fn trailing_bytes_are_rejected() {
    let mut configure = encode_configure(&[(1, vec![] as Vec<String>)]);
    configure.push(0);
    assert_eq!(decode_configure(&configure), None);

    let mut remember = encode_remember(1, "a", &[]);
    remember.push(0);
    assert_eq!(decode_remember(&remember), None);
}

#[test]
fn an_oversized_uid_count_is_rejected() {
    let mut encoded = encode_configure(&[]);
    encoded[1..5].copy_from_slice(&1u32.to_le_bytes());
    assert_eq!(decode_configure(&encoded), None);
}

#[test]
fn invalid_utf8_in_a_domain_is_rejected() {
    let mut encoded = encode_configure(&[(1, vec!["ab".to_string()])]);
    // layout(1) + count(4) + uid(4) + domain_count(4) + len(4) = 17
    encoded[17] = 0xff;
    assert_eq!(decode_configure(&encoded), None);
}

#[test]
fn remember_round_trip_keeps_addresses_and_ttls() {
    let records = vec![
        (vec![203, 0, 113, 7], 300),
        (
            vec![0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
            0,
        ),
    ];
    let encoded = encode_remember(-1, "Example.COM.", &records);
    assert_eq!(
        decode_remember(&encoded),
        Some(RememberRequest {
            uid: -1,
            question_name: "Example.COM.".to_string(),
            records,
        })
    );
}

#[test]
fn a_truncated_remember_payload_is_rejected() {
    let encoded = encode_remember(1, "q.example.", &[(vec![1, 2, 3, 4], 5)]);
    for cut in 0..encoded.len() {
        assert_eq!(decode_remember(&encoded[..cut]), None, "cut at {cut}");
    }
}

#[test]
fn an_address_that_is_not_4_or_16_bytes_is_rejected() {
    let mut encoded = encode_remember(1, "q", &[]);
    // Flip the record count to 1 and append a 5-byte address with its TTL.
    let position = encoded.len() - 4;
    encoded[position..].copy_from_slice(&1u32.to_le_bytes());
    encoded.push(5);
    encoded.extend_from_slice(&[1, 2, 3, 4, 5]);
    encoded.extend_from_slice(&60u32.to_le_bytes());
    assert_eq!(decode_remember(&encoded), None);
}

#[test]
fn invalid_utf8_in_the_question_is_rejected() {
    let mut encoded = encode_remember(1, "ab", &[]);
    // layout(1) + uid(4) + qname_len(4) = 9 is the first question byte.
    encoded[9] = 0xff;
    assert_eq!(decode_remember(&encoded), None);
}
