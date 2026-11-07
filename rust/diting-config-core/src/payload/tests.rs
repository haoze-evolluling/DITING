//! Layout round trips for both sides of the ABI.

use super::*;

fn request(op: u8) -> Vec<u8> {
    vec![op]
}

fn push_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn push_i64(out: &mut Vec<u8>, value: i64) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn status(response: &[u8]) -> u8 {
    response[0]
}

fn ok_body(response: &[u8]) -> &[u8] {
    assert_eq!(status(response), STATUS_OK);
    &response[1..]
}

fn error_text(response: &[u8]) -> String {
    assert_eq!(status(response), STATUS_ERROR);
    let mut reader = Reader::new(&response[1..]);
    let text = reader.text().expect("message");
    assert!(reader.at_end());
    text
}

#[test]
fn protocol_and_response_type_are_one_integer() {
    let mut payload = request(OP_PROTOCOL);
    push_text(&mut payload, "doh");
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    let body = ok_body(&response);
    assert_eq!(body, &1i64.to_le_bytes());

    let mut payload = request(OP_RESPONSE_TYPE);
    push_text(&mut payload, "nxdomain");
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    let body = ok_body(&response);
    assert_eq!(body, &0i64.to_le_bytes());
}

#[test]
fn doq_url_returns_host_and_port() {
    let mut payload = request(OP_DOQ_URL);
    push_text(&mut payload, "quic://dns.adguard.com:8853");
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    let mut reader = Reader::new(ok_body(&response));
    assert_eq!(reader.text().unwrap(), "dns.adguard.com");
    assert_eq!(reader.text().unwrap(), "8853");
    assert!(reader.at_end());
}

#[test]
fn domain_normalization_round_trips() {
    let mut payload = request(OP_DOMAIN);
    push_text(&mut payload, " Example.COM. ");
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    let mut reader = Reader::new(ok_body(&response));
    assert_eq!(reader.text().unwrap(), "example.com");
}

#[test]
fn rewrite_returns_three_texts() {
    let mut payload = request(OP_REWRITE);
    push_i64(&mut payload, 2);
    push_text(&mut payload, "1.2.3.4");
    push_text(&mut payload, "Example.COM.");
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    let mut reader = Reader::new(ok_body(&response));
    assert_eq!(reader.text().unwrap(), "example.com");
    assert_eq!(reader.text().unwrap(), "1.2.3.4");
    assert_eq!(reader.text().unwrap(), "");
    assert!(reader.at_end());

    // Nothing survives: all three fields are empty, which is how Go learns to drop the value.
    let mut payload = request(OP_REWRITE);
    push_i64(&mut payload, 1);
    push_text(&mut payload, "  ");
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    let mut reader = Reader::new(ok_body(&response));
    assert_eq!(reader.text().unwrap(), "");
    assert_eq!(reader.text().unwrap(), "");
    assert_eq!(reader.text().unwrap(), "");
}

#[test]
fn dns_config_round_trips_and_reports_errors() {
    let mut payload = request(OP_DNS_CONFIG);
    push_text(&mut payload, "single");
    push_text(&mut payload, "NXDOMAIN");
    push_i64(&mut payload, 1);
    push_i64(&mut payload, 0);
    push_i64(&mut payload, 0);
    push_i64(&mut payload, 0);
    push_i64(&mut payload, 1);
    push_text(&mut payload, "id-1");
    push_text(&mut payload, "plain");
    push_text(&mut payload, "1.1.1.1:53");
    push_text(&mut payload, "");
    push_i64(&mut payload, 3);
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    let mut reader = Reader::new(ok_body(&response));
    assert_eq!(reader.text().unwrap(), "single");
    assert_eq!(reader.i64().unwrap(), 1);
    assert_eq!(reader.i64().unwrap(), 1);
    assert_eq!(reader.i64().unwrap(), 5);
    assert_eq!(reader.i64().unwrap(), 60);
    assert_eq!(reader.i64().unwrap(), 300);
    assert_eq!(reader.i64().unwrap(), 1);
    assert_eq!(reader.text().unwrap(), "id-1");
    assert_eq!(reader.text().unwrap(), "PLAIN");
    assert_eq!(reader.text().unwrap(), "1.1.1.1:53");
    assert_eq!(reader.text().unwrap(), "");
    assert_eq!(reader.i64().unwrap(), 3);
    assert!(reader.at_end());

    // A rejected config comes back as an error body, not a decode failure.
    let mut payload = request(OP_DNS_CONFIG);
    push_text(&mut payload, "nope");
    push_text(&mut payload, "");
    push_i64(&mut payload, 0);
    push_i64(&mut payload, 0);
    push_i64(&mut payload, 0);
    push_i64(&mut payload, 0);
    push_i64(&mut payload, 0);
    let decoded = decode_request(&payload).expect("request");
    let response = encode_response(handle(decoded));
    assert_eq!(error_text(&response), "unsupported DNS mode \"nope\"");
}

#[test]
fn malformed_payloads_are_rejected() {
    // No opcode at all.
    assert!(decode_request(&[]).is_none());
    // Unknown opcode.
    assert!(decode_request(&[9]).is_none());
    // Trailing bytes.
    let mut payload = request(OP_DOMAIN);
    push_text(&mut payload, "a.example");
    payload.push(0);
    assert!(decode_request(&payload).is_none());
    // Text longer than the payload.
    let mut payload = request(OP_DOMAIN);
    payload.extend_from_slice(&1000u32.to_le_bytes());
    assert!(decode_request(&payload).is_none());
    // A count that cannot be satisfied is rejected before allocating.
    let mut payload = request(OP_REWRITE);
    push_i64(&mut payload, i64::MAX);
    assert!(decode_request(&payload).is_none());
    let mut payload = request(OP_REWRITE);
    push_i64(&mut payload, -1);
    assert!(decode_request(&payload).is_none());
    // An `enabled` flag outside 0/1.
    let mut payload = request(OP_DNS_CONFIG);
    push_text(&mut payload, "single");
    push_text(&mut payload, "");
    push_i64(&mut payload, 2);
    assert!(decode_request(&payload).is_none());
}
