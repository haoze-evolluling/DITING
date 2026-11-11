//! The SOCKS5 codec: byte-exact shapes, the need-more contract of the reply parser and the
//! datagram framing.

use super::*;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[test]
fn greeting_offers_auth_only_when_credentials_exist() {
    assert_eq!(greeting("", ""), vec![0x05, 0x01, 0x00]);
    assert_eq!(greeting("alice", ""), vec![0x05, 0x02, 0x00, 0x02]);
    assert_eq!(greeting("", "pw"), vec![0x05, 0x02, 0x00, 0x02]);
    assert_eq!(greeting("alice", "pw"), vec![0x05, 0x02, 0x00, 0x02]);
}

#[test]
fn method_reply_reads_the_selection() {
    assert_eq!(method_reply(&[0x05, 0x00]).unwrap(), AuthMethod::None);
    assert_eq!(method_reply(&[0x05, 0x02]).unwrap(), AuthMethod::UserPass);
    assert_eq!(AuthMethod::None.code(), 0x00);
    assert_eq!(AuthMethod::UserPass.code(), 0x02);

    assert_eq!(
        method_reply(&[0x05, 0xff]).unwrap_err(),
        "SOCKS5 proxy rejected authentication methods"
    );
    assert_eq!(
        method_reply(&[0x05, 0x01]).unwrap_err(),
        "unsupported SOCKS5 authentication method 1"
    );
    assert_eq!(
        method_reply(&[0x04, 0x00]).unwrap_err(),
        "invalid SOCKS5 greeting response"
    );
    assert_eq!(
        method_reply(&[0x05]).unwrap_err(),
        "invalid SOCKS5 greeting response"
    );
    assert_eq!(
        method_reply(&[]).unwrap_err(),
        "invalid SOCKS5 greeting response"
    );
}

#[test]
fn auth_bytes_are_length_prefixed() {
    assert_eq!(hex(&auth_request("bob", "")), "0103626f6200");
    assert_eq!(hex(&auth_request("a", "bc")), "010161026263");
    assert!(auth_reply(&[0x01, 0x00]).is_ok());
    assert_eq!(
        auth_reply(&[0x01, 0x01]).unwrap_err(),
        "SOCKS5 authentication failed"
    );
    // The version byte is never checked: only the status byte decides.
    assert!(auth_reply(&[0x00, 0x00]).is_ok());
    assert_eq!(
        auth_reply(&[0x01]).unwrap_err(),
        "SOCKS5 authentication failed"
    );
}

#[test]
fn address_encoding_matches_the_wire_form() {
    assert_eq!(hex(&address("1.2.3.4:80").unwrap()), "01010203040050");
    assert_eq!(
        hex(&address("[::1]:53").unwrap()),
        "04000000000000000000000000000000010035"
    );
    assert_eq!(
        hex(&address("[::ffff:127.0.0.1]:9").unwrap()),
        "017f0000010009"
    );
    assert_eq!(
        hex(&address("example.com:8080").unwrap()),
        "030b6578616d706c652e636f6d1f90"
    );
    assert_eq!(
        hex(&address("EXAMPLE.com:65535").unwrap()),
        "030b4558414d504c452e636f6dffff"
    );
    assert_eq!(
        hex(&address("example.com:0").unwrap()),
        "030b6578616d706c652e636f6d0000"
    );
    // A literal Go rejects becomes a domain, exactly like before.
    assert_eq!(
        hex(&address("1.2.3.4.5:80").unwrap()),
        "0309312e322e332e342e350050"
    );
    assert_eq!(
        hex(&address("[fe80::1%25eth0]:53").unwrap()),
        "030e666538303a3a31253235657468300035"
    );

    let longest = format!("{}:1", "b".repeat(255));
    assert_eq!(address(&longest).unwrap()[0], 0x03);
    assert_eq!(
        address(&format!("{}:1", "b".repeat(256))).unwrap_err(),
        "SOCKS5 target hostname length is invalid"
    );
    assert_eq!(
        address(":80").unwrap_err(),
        "SOCKS5 target hostname length is invalid"
    );
}

#[test]
fn address_errors_carry_the_go_texts() {
    assert_eq!(
        address("example.com:abc").unwrap_err(),
        "invalid target port \"abc\""
    );
    assert_eq!(
        address("example.com:65536").unwrap_err(),
        "invalid target port \"65536\""
    );
    assert_eq!(address("[::1]:").unwrap_err(), "invalid target port \"\"");
    assert_eq!(
        address("nocolon").unwrap_err(),
        "invalid target \"nocolon\": address nocolon: missing port in address"
    );
    assert_eq!(
        address("a:b:c:53").unwrap_err(),
        "invalid target \"a:b:c:53\": address a:b:c:53: too many colons in address"
    );
    // Atoi accepts a sign, so `+8` is a port.
    assert_eq!(hex(&address("host:+8").unwrap()), "0304686f73740008");
}

#[test]
fn request_prefixes_command_and_reserved_byte() {
    assert_eq!(
        hex(&request(COMMAND_CONNECT, "h:1").unwrap()),
        "0501000301680001"
    );
    assert_eq!(hex(&udp_associate_request()), "05030001000000000000");
}

#[test]
fn reply_parser_asks_for_the_whole_frame() {
    // Header alone is not enough for an IPv4 relay: it needs ten bytes.
    assert_eq!(parse_reply(&[]).unwrap(), ReplyParse::NeedMore(4));
    assert_eq!(
        parse_reply(&[0x05, 0x00, 0x00, 0x01]).unwrap(),
        ReplyParse::NeedMore(10)
    );
    assert_eq!(
        parse_reply(&[0x05, 0x00, 0x00, 0x03]).unwrap(),
        ReplyParse::NeedMore(5)
    );
    assert_eq!(
        parse_reply(&[0x05, 0x00, 0x00, 0x03, 3]).unwrap(),
        ReplyParse::NeedMore(10)
    );
}

#[test]
fn reply_parser_decodes_every_address_shape() {
    assert_eq!(
        parse_reply(&[0x05, 0x00, 0x00, 0x01, 1, 2, 3, 4, 0x04, 0x38]).unwrap(),
        ReplyParse::Done {
            address: "1.2.3.4:1080".to_string()
        }
    );
    let v6 = [
        0x05, 0x00, 0x00, 0x04, 0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x00,
        0x35,
    ];
    assert_eq!(
        parse_reply(&v6).unwrap(),
        ReplyParse::Done {
            address: "[2001:db8::1]:53".to_string()
        }
    );
    let mut domain = vec![0x05, 0x00, 0x00, 0x03, 11];
    domain.extend_from_slice(b"relay.local");
    domain.extend_from_slice(&[0x1f, 0x90]);
    assert_eq!(
        parse_reply(&domain).unwrap(),
        ReplyParse::Done {
            address: "relay.local:8080".to_string()
        }
    );
    // A zero-length domain is legal and joins to `:port`.
    assert_eq!(
        parse_reply(&[0x05, 0x00, 0x00, 0x03, 0, 0, 0x35]).unwrap(),
        ReplyParse::Done {
            address: ":53".to_string()
        }
    );
}

#[test]
fn reply_errors_use_the_status_byte() {
    assert_eq!(
        parse_reply(&[0x05, 0x01, 0x00, 0x01, 1, 2, 3, 4, 0, 1]).unwrap_err(),
        "SOCKS5 request failed with code 1"
    );
    assert_eq!(
        parse_reply(&[0x05, 0x08, 0x00, 0x01, 1, 2, 3, 4, 0, 1]).unwrap_err(),
        "SOCKS5 request failed with code 8"
    );
    // A bad version is reported with the status byte of that frame (0 here).
    assert_eq!(
        parse_reply(&[0x04, 0x00, 0x00, 0x01, 1, 2, 3, 4, 0, 1]).unwrap_err(),
        "SOCKS5 request failed with code 0"
    );
    assert_eq!(
        parse_reply(&[0x05, 0x00, 0x00, 0x02, 0, 0]).unwrap_err(),
        "invalid SOCKS5 address type 2"
    );
}

#[test]
fn datagram_round_trip() {
    let framed = datagram("1.2.3.4:53", &[0xaa, 0xbb]).unwrap();
    assert_eq!(hex(&framed), "00000001010203040035aabb");
    let view = parse_datagram(&framed[3..]).unwrap();
    assert_eq!(view.address, "1.2.3.4:53");
    assert!(view.host_is_ip);
    assert_eq!(&framed[3 + view.offset..], &[0xaa, 0xbb]);

    let framed = datagram("relay.local:8080", &[]).unwrap();
    assert_eq!(hex(&framed), "000000030b72656c61792e6c6f63616c1f90");
    let view = parse_datagram(&framed[3..]).unwrap();
    assert_eq!(view.address, "relay.local:8080");
    assert!(!view.host_is_ip);
    assert_eq!(view.offset, 15);
}

#[test]
fn datagram_truncation_reports_go_io_errors() {
    assert_eq!(parse_datagram(&[]).unwrap_err(), "EOF");
    assert_eq!(
        parse_datagram(&[0x05, 0, 0]).unwrap_err(),
        "invalid SOCKS5 address type 5"
    );
    assert_eq!(
        parse_datagram(&[0x01, 1, 2, 3, 4, 0]).unwrap_err(),
        "unexpected EOF"
    );
    assert_eq!(
        parse_datagram(&[0x03, 5, b'a']).unwrap_err(),
        "unexpected EOF"
    );
    assert_eq!(parse_datagram(&[0x03]).unwrap_err(), "EOF");
    assert_eq!(parse_datagram(&[0x01, 1, 2]).unwrap_err(), "unexpected EOF");
}

#[test]
fn datagram_domain_may_be_a_literal_ip() {
    // ATYP=domain carrying `9.8.7.6`: Go called `net.ParseIP` on the decoded text, so it counts.
    let mut raw = vec![0x03, 7];
    raw.extend_from_slice(b"9.8.7.6");
    raw.extend_from_slice(&[0, 53]);
    let view = parse_datagram(&raw).unwrap();
    assert_eq!(view.address, "9.8.7.6:53");
    assert!(view.host_is_ip);
}
