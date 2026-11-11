//! `ParseIPFromArpa`, line by line.

use super::*;

#[test]
fn reads_ipv4_reverse_names() {
    assert_eq!(
        parse_arpa("1.1.168.192.in-addr.arpa."),
        Some(Addr::V4([192, 168, 1, 1]))
    );
    // The trailing dot is optional: the old code trimmed dots before looking at the suffix.
    assert_eq!(
        parse_arpa("1.1.168.192.in-addr.arpa"),
        Some(Addr::V4([192, 168, 1, 1]))
    );
    assert_eq!(
        parse_arpa("1.1.168.192.IN-ADDR.ARPA."),
        Some(Addr::V4([192, 168, 1, 1]))
    );
    assert_eq!(
        parse_arpa(".1.1.168.192.in-addr.arpa."),
        Some(Addr::V4([192, 168, 1, 1]))
    );
}

#[test]
fn reads_ipv6_reverse_names() {
    let expected = Addr::V6([0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
    assert_eq!(
        parse_arpa("1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa."),
        Some(expected)
    );
    assert_eq!(
        parse_arpa("1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.B.D.0.1.0.0.2.IP6.ARPA."),
        Some(expected)
    );
    // The loopback address, whose last label carries the only non-zero nibble.
    let mut loopback = [0u8; 16];
    loopback[15] = 1;
    assert_eq!(
        parse_arpa("1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa."),
        Some(Addr::V6(loopback))
    );
}

#[test]
fn collapses_a_mapped_reverse_name() {
    // `::ffff:1.2.3.4` written out in nibbles resolves to the IPv4 address, because the old code
    // went through `net.IP.String()` (which prints the mapped form as a quad) for its key.
    let mut bytes = [0u8; 16];
    bytes[10] = 0xff;
    bytes[11] = 0xff;
    bytes[12] = 1;
    bytes[13] = 2;
    bytes[14] = 3;
    bytes[15] = 4;
    assert_eq!(collapse_v6(bytes), Addr::V4([1, 2, 3, 4]));
}

#[test]
fn rejects_names_without_an_address() {
    for name in [
        "1.2.3.4.5.in-addr.arpa.",
        "1.2.3.in-addr.arpa.",
        "invalid.in-addr.arpa",
        "in-addr.arpa.",
        "ip6.arpa.",
        "example.com.",
        "",
        // 31 labels instead of 32.
        "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.",
        // A label that is not one hex digit.
        "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.gg.ip6.arpa.",
        // An empty label in the middle is not a nibble.
        "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0..ip6.arpa.",
    ] {
        assert_eq!(parse_arpa(name), None, "{name}");
    }
    // A dotted quad with a leading zero fails `net.ParseIP`, which the old code relied on.
    assert_eq!(parse_arpa("1.1.168.01.in-addr.arpa."), None);
}
