//! Unit tests for the text payload.

use super::*;

#[test]
fn text_round_trips() {
    let tag = r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h=a.com">"#;
    let payload = encode_text(tag.as_bytes());
    assert_eq!(payload[0], LAYOUT_VERSION);
    assert_eq!(&payload[1..5], &(tag.len() as u32).to_le_bytes());
    assert_eq!(decode_text(&payload).unwrap(), tag);
}

#[test]
fn empty_text_round_trips() {
    let payload = encode_text(b"");
    assert_eq!(decode_text(&payload).unwrap(), "");
}

#[test]
fn a_drifted_layout_is_rejected() {
    let mut payload = encode_text(b"x");
    payload[0] = LAYOUT_VERSION + 1;
    assert!(decode_text(&payload).is_err());
}

#[test]
fn truncated_and_trailing_payloads_are_rejected() {
    let payload = encode_text(b"abc");
    for end in 0..payload.len() {
        assert!(
            decode_text(&payload[..end]).is_err(),
            "truncation at {end} was accepted"
        );
    }
    let mut longer = payload.clone();
    longer.push(0);
    assert!(decode_text(&longer).is_err());
}

#[test]
fn a_declared_length_past_the_end_is_rejected() {
    let mut payload = encode_text(b"abc");
    payload[1..5].copy_from_slice(&99u32.to_le_bytes());
    assert!(decode_text(&payload).is_err());
}
