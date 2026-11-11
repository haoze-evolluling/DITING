use super::*;
use crate::addr::map_v4;

#[test]
fn parse_cidr_masks_the_address_like_go() {
    let cidr = parse_cidr("2001:db8::1/32").unwrap();
    assert_eq!(cidr.ones, 32);
    assert_eq!(cidr.bits, 128);
    assert_eq!(cidr.addr16[..4], [0x20, 0x01, 0x0d, 0xb8]);
    assert!(cidr.addr16[4..].iter().all(|byte| *byte == 0));
    assert_eq!(
        cidr.net,
        Net::V6 {
            number: cidr.addr16,
            mask: crate::addr::mask16(32),
        }
    );
}

#[test]
fn parse_cidr_keeps_ipv4_networks_in_four_byte_width() {
    let cidr = parse_cidr("10.11.12.13/24").unwrap();
    assert_eq!(cidr.bits, 32);
    assert_eq!(cidr.ones, 24);
    assert_eq!(
        cidr.net,
        Net::V4 {
            number: [10, 11, 12, 0],
            mask: crate::addr::mask4(24),
        }
    );
    // `IPNet.IP` is 4 bytes here, and `To16` maps it again.
    assert_eq!(cidr.addr16, map_v4([10, 11, 12, 0]));
}

#[test]
fn an_ipv4_mapped_network_collapses_and_then_matches_every_ipv4() {
    // This is the `::ffff:0:0/96` default exclusion: `networkNumberAndMask` folds the network to
    // `0.0.0.0` with the *last four* mask bytes, which are zero — so any IPv4 address "is in" it.
    let cidr = parse_cidr("::ffff:0:0/96").unwrap();
    assert_eq!(
        cidr.net,
        Net::V4 {
            number: [0, 0, 0, 0],
            mask: [0, 0, 0, 0],
        }
    );
    assert_eq!(cidr.addr16, map_v4([0, 0, 0, 0]));
    assert!(cidr.net.contains(&[1, 2, 3, 4]));
    assert!(cidr.net.contains(&map_v4([1, 2, 3, 4])));
    // 16-byte addresses that are not mapped do not match an IPv4 network.
    assert!(!cidr.net.contains(&[0u8; 16]));
}

#[test]
fn parse_cidr_accepts_leading_zeros_in_the_mask() {
    assert_eq!(parse_cidr("64:ff9b::/096").unwrap().ones, 96);
    assert_eq!(parse_cidr("64:ff9b::/0032").unwrap().ones, 32);
}

#[test]
fn parse_cidr_errors_match_net_parse_cidr() {
    for text in [
        "",
        "64:ff9b::",
        "/96",
        "2001:db8::/-1",
        "2001:db8::/+96",
        "2001:db8::/ 96",
        "2001:db8::/96 ",
        "2001:db8::/96/96",
        "2001:db8::/9 6",
        "2001:db8::/129",
        "2001:db8::/65536",
        "1.2.3.4/33",
        "01.2.3.4/24",
        "1.2.3/24",
        "1.2.3.4.5/24",
        "fe80::%eth0/10",
        "invalid-cidr",
        "(64:ff9b::/96)",
    ] {
        assert_eq!(parse_cidr(text), Err(PrefixError::Parse), "{text}");
    }
}

#[test]
fn dns64_prefixes_accept_only_the_rfc6052_lengths() {
    for (text, ones) in [
        ("64:ff9b::/96", 96),
        ("2001:db8::/32", 32),
        ("2001:db8:100::/40", 40),
        ("2001:db8:1234::/48", 48),
        ("2001:db8:1234:5600::/56", 56),
        ("2001:db8:1234:5678::/64", 64),
    ] {
        let (prefix, _) = parse_dns64_prefix(text).unwrap();
        assert_eq!(prefix.ones, ones);
    }

    for text in [
        "2001:db8::/28",
        "2001:db8::/65",
        "2001:db8::/120",
        "2001:db8::/0",
        "2001:db8::/128",
        "::/96", // parses, but the /96-collapsed network is IPv4-shaped only in `Net`, not here
        "10.0.0.0/8",
        "1.2.3.4/32",
        "0.0.0.0/0",
        "::ffff:1.2.3.4/128",
    ] {
        match text {
            "::/96" => assert!(parse_dns64_prefix(text).is_ok(), "{text}"),
            _ => assert_eq!(parse_dns64_prefix(text), Err(PrefixError::Length), "{text}"),
        }
    }
}

#[test]
fn well_known_prefix_is_the_rfc6052_default() {
    let prefix = well_known_prefix();
    assert_eq!(prefix.ones, 96);
    assert_eq!(&prefix.addr[..4], &[0x00, 0x64, 0xff, 0x9b]);
}

#[test]
fn unspecified_covers_the_three_shapes_go_reports() {
    assert!(is_unspecified(&[0, 0, 0, 0]));
    assert!(is_unspecified(&[0u8; 16]));
    assert!(is_unspecified(&map_v4([0, 0, 0, 0])));
    assert!(!is_unspecified(&map_v4([0, 0, 0, 1])));
    assert!(!is_unspecified(&[0u8; 15]));
    // `::1` is not unspecified.
    let mut loopback = [0u8; 16];
    loopback[15] = 1;
    assert!(!is_unspecified(&loopback));
}
