//! `net` behaviour pinned by hand: the parsers come from different libraries on the two sides, so
//! the accept/reject table (and the text of the errors) is asserted here.

use super::*;

#[test]
fn parse_ip_matches_net_parse_ip() {
    // Accepted: dotted quad, IPv6 shorthands, IPv4-mapped and IPv4-embedded forms.
    assert_eq!(
        hex(&parse_ip("1.2.3.4").unwrap()),
        "00000000000000000000ffff01020304"
    );
    assert_eq!(
        hex(&parse_ip("127.0.0.1").unwrap()),
        "00000000000000000000ffff7f000001"
    );
    assert_eq!(
        hex(&parse_ip("::1").unwrap()),
        "00000000000000000000000000000001"
    );
    assert_eq!(
        hex(&parse_ip("::").unwrap()),
        "00000000000000000000000000000000"
    );
    assert_eq!(
        hex(&parse_ip("0:0:0:0:0:0:0:1").unwrap()),
        "00000000000000000000000000000001"
    );
    assert_eq!(
        hex(&parse_ip("::ffff:127.0.0.1").unwrap()),
        "00000000000000000000ffff7f000001"
    );
    assert_eq!(
        hex(&parse_ip("::1.2.3.4").unwrap()),
        "00000000000000000000000001020304"
    );
    assert_eq!(
        hex(&parse_ip("2001:DB8::1").unwrap()),
        "20010db8000000000000000000000001"
    );

    // Rejected by both: leading zeros, wrong field counts, zones, hostnames, whitespace, empties.
    for text in [
        "",
        " ",
        "not-an-ip",
        "1.2.3",
        "1.2.3.4.5",
        "01.2.3.4",
        "0x7f.0.0.1",
        "1::2::3::4",
        "fe80::1%eth0",
        "[::1]",
        "::1 ",
        " 1.2.3.4",
        "1.2.3.4:80",
        "12345::",
    ] {
        assert!(parse_ip(text).is_none(), "{text} must not parse");
    }
}

#[test]
fn loopback_and_text_follow_go() {
    assert!(is_loopback(&parse_ip("127.0.0.1").unwrap()));
    assert!(is_loopback(&parse_ip("127.255.255.254").unwrap()));
    assert!(is_loopback(&parse_ip("::1").unwrap()));
    assert!(is_loopback(&parse_ip("::ffff:127.0.0.1").unwrap()));
    assert!(!is_loopback(&parse_ip("128.0.0.1").unwrap()));
    assert!(!is_loopback(&parse_ip("0.0.0.0").unwrap()));
    assert!(!is_loopback(&parse_ip("::").unwrap()));

    assert_eq!(ip_text(&parse_ip("::ffff:127.0.0.1").unwrap()), "127.0.0.1");
    assert_eq!(ip_text(&parse_ip("0:0:0:0:0:0:0:1").unwrap()), "::1");
    assert_eq!(
        ip_text(&parse_ip("2001:db8:0:0:0:0:0:1").unwrap()),
        "2001:db8::1"
    );
}

#[test]
fn split_host_port_matches_go() {
    assert_eq!(
        split_host_port("example.com:80").unwrap(),
        ("example.com", "80")
    );
    assert_eq!(split_host_port("[::1]:53").unwrap(), ("::1", "53"));
    assert_eq!(
        split_host_port("[fe80::1%eth0]:53").unwrap(),
        ("fe80::1%eth0", "53")
    );
    assert_eq!(split_host_port(":80").unwrap(), ("", "80"));
    assert_eq!(split_host_port("host:port").unwrap(), ("host", "port"));

    assert_eq!(split_host_port("").unwrap_err(), "missing port in address");
    assert_eq!(
        split_host_port("nocolon").unwrap_err(),
        "address nocolon: missing port in address"
    );
    assert_eq!(
        split_host_port("a:b:c:53").unwrap_err(),
        "address a:b:c:53: too many colons in address"
    );
    assert_eq!(
        split_host_port("[::1:53").unwrap_err(),
        "address [::1:53: missing ']' in address"
    );
    assert_eq!(
        split_host_port("[::1]").unwrap_err(),
        "address [::1]: missing port in address"
    );
    assert_eq!(
        split_host_port("[::1]:5:3").unwrap_err(),
        "address [::1]:5:3: too many colons in address"
    );
    assert_eq!(
        split_host_port("[::1]53").unwrap_err(),
        "address [::1]53: missing port in address"
    );
    assert_eq!(
        split_host_port("[::1]:53[").unwrap_err(),
        "address [::1]:53[: unexpected '[' in address"
    );
    assert_eq!(
        split_host_port("[::1]:53]").unwrap_err(),
        "address [::1]:53]: unexpected ']' in address"
    );
}

#[test]
fn join_host_port_brackets_colons() {
    assert_eq!(join_host_port_text("example.com", "80"), "example.com:80");
    assert_eq!(join_host_port_text("::1", "853"), "[::1]:853");
    assert_eq!(join_host_port_text("", "53"), ":53");
    // The text port is kept verbatim, even when it is not a number: the resolver endpoints are
    // validated by shape only, so `net.JoinHostPort` must not reject or rewrite it.
    assert_eq!(join_host_port_text("example.com", "053"), "example.com:053");
    assert_eq!(join_host_port_text("example.com", ""), "example.com:");
    assert_eq!(join_host_port("example.com", 80), "example.com:80");
    assert_eq!(join_host_port("::1", 53), "[::1]:53");
    assert_eq!(join_host_port("", 53), ":53");
    assert_eq!(join_host_port("relay.local", 8080), "relay.local:8080");
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
