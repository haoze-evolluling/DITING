//! Payload round-trips and the rejection paths a stale Go/Rust pair runs into.

use super::*;
use crate::hosts::Source;
use crate::ip::parse_ip;

#[test]
fn sources_round_trip() {
    let sources = vec![
        Source::File(PathBuf::from("C:/Windows/System32/drivers/etc/hosts")),
        Source::Text("127.0.0.1 localhost\n".to_string()),
        Source::Text(String::new()),
    ];
    let encoded = encode_sources(&sources);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(decode_sources(&encoded).expect("decode"), sources);
}

#[test]
fn sources_reject_a_stale_layout_or_a_bad_kind() {
    let mut encoded = encode_sources(&[Source::Text("x".to_string())]);
    encoded[0] = LAYOUT_VERSION + 1;
    assert!(decode_sources(&encoded).is_err());

    let mut encoded = encode_sources(&[Source::Text("x".to_string())]);
    encoded[5] = 9;
    assert!(decode_sources(&encoded).is_err());

    let mut encoded = encode_sources(&[Source::Text("x".to_string())]);
    encoded.pop();
    assert!(decode_sources(&encoded).is_err());

    let mut encoded = encode_sources(&[Source::Text("x".to_string())]);
    encoded.push(0);
    assert!(decode_sources(&encoded).is_err());
}

#[test]
fn info_carries_the_error_and_the_loaded_paths() {
    let payload = encode_info(
        &["a.hosts".to_string(), "b.hosts".to_string()],
        Some("b.hosts: nope"),
    );
    let mut reader = Reader::new(&payload);
    assert_eq!(reader.layout("info").expect("layout"), LAYOUT_VERSION);
    assert_eq!(reader.u8("has_error").expect("flag"), 1);
    assert_eq!(reader.text().expect("error"), "b.hosts: nope");
    assert_eq!(reader.u32("count").expect("count"), 2);
    assert_eq!(reader.text().expect("first"), "a.hosts");
    assert_eq!(reader.text().expect("second"), "b.hosts");
    assert!(reader.expect_end().is_ok());

    let payload = encode_info(&[], None);
    let mut reader = Reader::new(&payload);
    reader.layout("info").expect("layout");
    assert_eq!(reader.u8("has_error").expect("flag"), 0);
    assert_eq!(reader.text().expect("error"), "");
    assert_eq!(reader.u32("count").expect("count"), 0);
}

#[test]
fn lookup_payload_carries_the_width_and_the_addresses() {
    let payload = encode_lookup(&[Addr::V4([1, 2, 3, 4]), Addr::V4([5, 6, 7, 8])]);
    let mut reader = Reader::new(&payload);
    reader.layout("lookup").expect("layout");
    assert_eq!(reader.u8("width").expect("width"), 4);
    assert_eq!(reader.u32("count").expect("count"), 2);
    assert_eq!(reader.bytes(4, "addr").expect("first"), &[1, 2, 3, 4]);
    assert_eq!(reader.bytes(4, "addr").expect("second"), &[5, 6, 7, 8]);
    assert!(reader.expect_end().is_ok());

    let payload = encode_lookup(&[]);
    let mut reader = Reader::new(&payload);
    reader.layout("lookup").expect("layout");
    assert_eq!(reader.u8("width").expect("width"), 4);
    assert_eq!(reader.u32("count").expect("count"), 0);
    assert!(reader.expect_end().is_ok());

    let payload = encode_lookup(&[parse_ip("2001:db8::1").expect("v6")]);
    assert_eq!(payload[1], 16);
    assert_eq!(payload.len(), 6 + 16);
}

#[test]
fn names_and_reverse_round_trip() {
    let payload = encode_names(&["a.home".to_string(), "b.home".to_string()]);
    let mut reader = Reader::new(&payload);
    reader.layout("names").expect("layout");
    assert_eq!(reader.u32("count").expect("count"), 2);
    assert_eq!(reader.text().expect("first"), "a.home");
    assert_eq!(reader.text().expect("second"), "b.home");
    assert!(reader.expect_end().is_ok());

    let payload = encode_reverse(Some("a.home"));
    assert_eq!(&payload[..2], &[LAYOUT_VERSION, 1]);
    let payload = encode_reverse(None);
    assert_eq!(&payload[..2], &[LAYOUT_VERSION, 0]);
    assert_eq!(payload.len(), 6);
}

#[test]
fn arpa_payload_carries_width_zero_for_a_miss() {
    let payload = encode_arpa_name("1.1.168.192.in-addr.arpa.");
    assert_eq!(payload, [LAYOUT_VERSION, 4, 192, 168, 1, 1]);

    let payload = encode_arpa_name(
        "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.",
    );
    assert_eq!(payload[1], 16);
    assert_eq!(payload.len(), 2 + 16);

    assert_eq!(encode_arpa_name("example.com."), [LAYOUT_VERSION, 0]);
}
