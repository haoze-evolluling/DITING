//! Boundary tests: the layout the Go encoder writes is decoded here byte for byte, and every
//! malformed frame is rejected instead of misread.

use super::*;

fn request(records: &[(u8, &[u8])]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(records.len() as u32).to_le_bytes());
    for (rrtype, address) in records {
        out.push(*rrtype);
        out.extend_from_slice(&(address.len() as u16).to_le_bytes());
        out.extend_from_slice(address);
    }
    out
}

#[test]
fn answer_requests_decode_into_borrowed_entries() {
    let payload = request(&[(1, &[1, 2, 3, 4]), (28, &[]), (5, &[9, 9])]);
    let entries = decode_answer_request(&payload).expect("well formed");
    assert_eq!(entries.len(), 3);
    assert_eq!(entries[0].rrtype, 1);
    assert_eq!(entries[0].address, &[1, 2, 3, 4]);
    assert_eq!(entries[1].address, &[] as &[u8]);
    assert_eq!(entries[2].rrtype, 5);
}

#[test]
fn malformed_answer_requests_are_rejected() {
    let valid = request(&[(1, &[1, 2, 3, 4])]);

    let mut wrong_layout = valid.clone();
    wrong_layout[0] = LAYOUT_VERSION + 1;
    assert_eq!(decode_answer_request(&wrong_layout), None);

    assert_eq!(decode_answer_request(&valid[..4]), None, "truncated header");

    let mut truncated = valid.clone();
    truncated.pop();
    assert_eq!(decode_answer_request(&truncated), None, "truncated address");

    let mut trailing = valid.clone();
    trailing.push(0);
    assert_eq!(decode_answer_request(&trailing), None, "trailing byte");

    let mut huge_count = request(&[]);
    huge_count[1..5].copy_from_slice(&u32::MAX.to_le_bytes());
    assert_eq!(decode_answer_request(&huge_count), None);

    // A zero-length address is legal (a hand-built record without one).
    let empty = request(&[(1, &[])]);
    let entries = decode_answer_request(&empty).expect("empty address");
    assert_eq!(entries[0].address, &[] as &[u8]);
}

#[test]
fn answer_responses_round_trip_and_reject_damage() {
    let payload = encode_answer_response(true, "0.0.0.0,::1");
    assert_eq!(payload[0], LAYOUT_VERSION);
    assert_eq!(payload[1], FLAG_BLOCKED);
    assert_eq!(
        decode_answer_response(&payload),
        Some((true, "0.0.0.0,::1".to_string()))
    );

    let clean = encode_answer_response(false, "");
    assert_eq!(decode_answer_response(&clean), Some((false, String::new())));

    let mut wrong_layout = payload.clone();
    wrong_layout[0] = 9;
    assert_eq!(decode_answer_response(&wrong_layout), None);

    let mut unknown_flags = payload.clone();
    unknown_flags[1] |= 0x80;
    assert_eq!(decode_answer_response(&unknown_flags), None);

    let mut short = payload.clone();
    short.pop();
    assert_eq!(decode_answer_response(&short), None);

    let mut long = payload.clone();
    long.push(b'x');
    assert_eq!(decode_answer_response(&long), None);

    let mut bad_utf8 = payload;
    let last = bad_utf8.len() - 1;
    bad_utf8[last] = 0xff;
    assert_eq!(decode_answer_response(&bad_utf8), None);
}
