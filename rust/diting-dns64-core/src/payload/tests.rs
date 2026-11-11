use super::*;

#[test]
fn prefixes_round_trip() {
    let prefixes = vec!["64:ff9b::/96".to_string(), " 2001:db8::/32 ".to_string()];
    let encoded = encode_prefixes(&prefixes);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(decode_prefixes(&encoded).unwrap(), prefixes);
}

#[test]
fn addresses_round_trip_with_their_width() {
    let four = [1u8, 2, 3, 4];
    let sixteen = [0x20u8, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1];
    let encoded = encode_addresses(&[&four, &sixteen, &[]]);
    let decoded = decode_addresses(&encoded).unwrap();
    assert_eq!(decoded.len(), 3);
    assert_eq!(decoded[0], four);
    assert_eq!(decoded[1], sixteen);
    assert!(decoded[2].is_empty());
}

#[test]
fn results_are_sixteen_byte_addresses() {
    let encoded = encode_result(&[[0u8; 16], [0xffu8; 16]]);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(encoded[1], 2);
    assert_eq!(encoded.len(), 2 + 32);
}

#[test]
fn stale_layouts_and_truncation_are_rejected() {
    let mut encoded = encode_prefixes(&["64:ff9b::/96".to_string()]);
    encoded[0] = 2;
    assert!(decode_prefixes(&encoded).unwrap_err().contains("layout"));

    let encoded = encode_prefixes(&["64:ff9b::/96".to_string()]);
    assert!(decode_prefixes(&encoded[..encoded.len() - 1]).is_err());

    let mut encoded = encode_addresses(&[&[1u8, 2, 3, 4]]);
    encoded[3] = 17; // width above 16
    assert!(decode_addresses(&encoded).unwrap_err().contains("width"));

    let mut trailing = encode_addresses(&[]);
    trailing.push(0);
    assert!(decode_addresses(&trailing)
        .unwrap_err()
        .contains("trailing"));
}
