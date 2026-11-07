use super::*;

#[test]
fn mark_requests_round_trip() {
    let encoded = encode_mark("blk|", "com.example.app", "1.2.3.4", 443, 6, "uid_blocked");
    assert_eq!(
        decode_mark(&encoded),
        Some(MarkRequest {
            prefix: "blk|".to_string(),
            app: "com.example.app".to_string(),
            dest: "1.2.3.4".to_string(),
            port: 443,
            protocol: 6,
            reason: "uid_blocked".to_string(),
        })
    );
}

#[test]
fn empty_fields_and_unicode_round_trip() {
    let encoded = encode_mark("", "", "", 0, 0, "");
    assert_eq!(
        decode_mark(&encoded),
        Some(MarkRequest {
            prefix: String::new(),
            app: String::new(),
            dest: String::new(),
            port: 0,
            protocol: 0,
            reason: String::new(),
        })
    );

    let encoded = encode_mark("", "名字", "例子.cn", 65535, 17, "原因");
    let decoded = decode_mark(&encoded).expect("valid payload");
    assert_eq!(decoded.app, "名字");
    assert_eq!(decoded.dest, "例子.cn");
    assert_eq!(decoded.reason, "原因");
}

#[test]
fn negative_numbers_round_trip() {
    let encoded = encode_mark("", "a", "b", -1, -2, "");
    let decoded = decode_mark(&encoded).expect("valid payload");
    assert_eq!(decoded.port, -1);
    assert_eq!(decoded.protocol, -2);
}

#[test]
fn a_drifted_version_is_rejected() {
    let mut encoded = encode_mark("", "a", "b", 1, 6, "");
    encoded[0] = LAYOUT_VERSION + 1;
    assert_eq!(decode_mark(&encoded), None);
}

#[test]
fn a_truncated_payload_is_rejected() {
    let encoded = encode_mark("blk|", "app", "dest", 443, 6, "reason");
    for cut in 0..encoded.len() {
        assert_eq!(decode_mark(&encoded[..cut]), None, "cut at {cut}");
    }
}

#[test]
fn trailing_bytes_are_rejected() {
    let mut encoded = encode_mark("", "a", "b", 1, 6, "");
    encoded.push(0);
    assert_eq!(decode_mark(&encoded), None);
}

#[test]
fn invalid_utf8_is_rejected() {
    let mut encoded = encode_mark("", "ab", "dest", 1, 6, "");
    // layout(1) + port(4) + protocol(4) + prefix_len(4) = 13 starts the app bytes.
    encoded[13] = 0xff;
    assert_eq!(decode_mark(&encoded), None);
}
