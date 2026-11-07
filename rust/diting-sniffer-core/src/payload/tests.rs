//! Payload layout cases shared with `android/engine/mitm_sniffer_payload_test.go`.

use crate::payload::{decode, encode, KIND_HTTP, KIND_TLS, KIND_UNKNOWN, LAYOUT_VERSION};

#[test]
fn encodes_and_decodes_a_classification() {
    let payload = encode(KIND_TLS, b"example.com");
    assert_eq!(payload[0], LAYOUT_VERSION);
    assert_eq!(payload[1], KIND_TLS);
    assert_eq!(&payload[2..6], &11u32.to_le_bytes());
    assert_eq!(decode(&payload), Ok((KIND_TLS, &b"example.com"[..])));
}

#[test]
fn unknown_carries_an_empty_host() {
    let payload = encode(KIND_UNKNOWN, b"");
    assert_eq!(decode(&payload), Ok((KIND_UNKNOWN, &b""[..])));
    assert_eq!(
        decode(&encode(KIND_HTTP, b"")).map(|(kind, _)| kind),
        Ok(KIND_HTTP)
    );
}

#[test]
fn rejects_a_malformed_payload() {
    assert!(decode(&[]).is_err());
    assert!(decode(&[LAYOUT_VERSION, KIND_TLS, 0, 0]).is_err());
    assert!(decode(&[LAYOUT_VERSION + 1, KIND_TLS, 0, 0, 0, 0]).is_err());
    assert!(decode(&[LAYOUT_VERSION, 9, 0, 0, 0, 0]).is_err());
    assert!(decode(&[LAYOUT_VERSION, KIND_HTTP, 2, 0, 0, 0, b'x']).is_err());
    assert!(decode(&[LAYOUT_VERSION, KIND_HTTP, 1, 0, 0, 0, b'x', b'y']).is_err());
}
