//! `net.ParseIP` behaviour, pinned by the corpus the Go parser produced.

use super::*;

#[test]
fn parses_dotted_quads() {
    assert_eq!(parse_ip("127.0.0.1"), Some(Addr::V4([127, 0, 0, 1])));
    assert_eq!(parse_ip("255.255.255.255"), Some(Addr::V4([255; 4])));
    // Go rejects leading zeros in dotted quads since 1.17, so this is not an address.
    assert_eq!(parse_ip("01.2.3.4"), None);
    assert_eq!(parse_ip("1.2.3"), None);
    assert_eq!(parse_ip("1.2.3.4.5"), None);
    assert_eq!(parse_ip("0x7f.0.0.1"), None);
}

#[test]
fn collapses_the_mapped_form() {
    let expected = Some(Addr::V4([1, 2, 3, 4]));
    assert_eq!(parse_ip("::ffff:1.2.3.4"), expected);
    assert_eq!(parse_ip("::FFFF:1.2.3.4"), expected);
    assert_eq!(parse_ip("0:0:0:0:0:ffff:1.2.3.4"), expected);
    // A quad that is *not* mapped keeps its 16 bytes, like Go's `To4` returning nil.
    assert_eq!(
        parse_ip("::1.2.3.4"),
        Some(Addr::V6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4]))
    );
    assert_eq!(
        parse_ip("::255.255.255.255"),
        Some(Addr::V6([
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255
        ]))
    );
}

#[test]
fn parses_ipv6_literals() {
    assert_eq!(parse_ip("::"), Some(Addr::V6([0; 16])));
    let mut expected = [0u8; 16];
    expected[0] = 0x20;
    expected[1] = 0x01;
    expected[2] = 0x0d;
    expected[3] = 0xb8;
    expected[15] = 1;
    assert_eq!(parse_ip("2001:db8::1"), Some(Addr::V6(expected)));
    assert_eq!(parse_ip("2001:DB8::1"), Some(Addr::V6(expected)));
    assert_eq!(parse_ip("12345::"), None);
    assert_eq!(parse_ip("::g"), None);
    assert_eq!(parse_ip("1::2::3::4"), None);
    assert_eq!(parse_ip("1:2:3:4:5:6:7:8:9"), None);
    assert_eq!(parse_ip("::ffff:01.2.3.4"), None);
}

#[test]
fn rejects_padding_and_zone_suffixes() {
    assert_eq!(parse_ip(" 127.0.0.1"), None);
    assert_eq!(parse_ip("1.2.3.4 "), None);
    assert_eq!(parse_ip(""), None);
    // The zone is cut before parsing, so the address itself is fine.
    assert_eq!(
        parse_hosts_address("1.2.3.4%eth0"),
        Some(Addr::V4([1, 2, 3, 4]))
    );
    assert_eq!(parse_hosts_address("fe80::1%eth0"), parse_ip("fe80::1"),);
    assert_eq!(parse_hosts_address("eth0%fe80::1"), None);
}

#[test]
fn round_trips_the_byte_forms() {
    for addr in [Addr::V4([1, 2, 3, 4]), Addr::V6([7; 16])] {
        assert_eq!(Addr::from_bytes(addr.as_bytes()), Some(addr));
        assert_eq!(addr.width(), addr.as_bytes().len());
    }
    assert_eq!(Addr::from_bytes(&[0u8; 5]), None);
    assert_eq!(Addr::from_bytes(&[]), None);
}

#[test]
fn collapse_v6_only_touches_the_mapped_form() {
    assert_eq!(
        collapse_v6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 8, 8, 8, 8]),
        Addr::V4([8, 8, 8, 8])
    );
    assert_eq!(collapse_v6([0; 16]), Addr::V6([0; 16]));
}
