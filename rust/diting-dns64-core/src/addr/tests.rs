use super::*;

#[test]
fn parse_addr_reports_the_family_of_the_text_form() {
    let (family, bytes) = parse_addr("192.0.2.1").unwrap();
    assert_eq!(family, Family::V4);
    assert_eq!(bytes, map_v4([192, 0, 2, 1]));

    let (family, bytes) = parse_addr("::ffff:192.0.2.1").unwrap();
    assert_eq!(family, Family::V6);
    assert_eq!(bytes, map_v4([192, 0, 2, 1]));

    let (family, bytes) = parse_addr("2001:db8::1").unwrap();
    assert_eq!(family, Family::V6);
    assert_eq!(bytes[..4], [0x20, 0x01, 0x0d, 0xb8]);
    assert_eq!(bytes[15], 1);
}

#[test]
fn parse_addr_rejects_what_netip_rejects() {
    for text in [
        "",
        " ",
        "1.2.3",
        "1.2.3.4.5",
        "01.2.3.4",
        "1.2.3.256",
        "::1%eth0",
        "1::2::3",
        ":::",
        "2001:db8::g",
        "2001:db8:: ",
        "(64:ff9b::)",
        ":",
        "::ffff:01.2.3.4",
    ] {
        assert!(parse_addr(text).is_none(), "{text} should not parse");
    }
}

#[test]
fn parse_addr_accepts_zones_are_not_reachable_because_we_reject_them() {
    // `net.ParseCIDR` rejects a zone after `ParseAddr` accepts it; rejecting here is the same
    // outcome, and it keeps the kernel from carrying a zone it would never use.
    assert!(parse_addr("fe80::1%eth0").is_none());
    assert!(parse_addr("fe80::1").is_some());
}

#[test]
fn to4_folds_only_the_mapped_form() {
    assert_eq!(to4(&[1, 2, 3, 4]), Some([1, 2, 3, 4]));
    assert_eq!(to4(&map_v4([1, 2, 3, 4])), Some([1, 2, 3, 4]));
    // `::` is *not* an IPv4 address for Go's To4, even though it is all zeros.
    assert_eq!(to4(&[0u8; 16]), None);
    // IPv4-compatible, not mapped.
    let mut compatible = [0u8; 16];
    compatible[12..].copy_from_slice(&[1, 2, 3, 4]);
    assert_eq!(to4(&compatible), None);
    assert_eq!(to4(&[1, 2, 3, 4, 5]), None);
    assert_eq!(to4(&[]), None);
}

#[test]
fn masks_follow_cidr_mask() {
    assert_eq!(mask16(0), [0u8; 16]);
    assert_eq!(mask16(128), [0xffu8; 16]);
    assert_eq!(mask16(96)[..12], [0xffu8; 12]);
    assert_eq!(mask16(96)[12..], [0u8; 4]);
    assert_eq!(mask16(10)[0], 0xff);
    assert_eq!(mask16(10)[1], 0xc0);
    assert_eq!(mask16(10)[2], 0x00);

    assert_eq!(mask4(32), [0xffu8; 4]);
    assert_eq!(mask4(8), [0xff, 0, 0, 0]);
    assert_eq!(mask4(0), [0u8; 4]);

    let masked = apply_mask16(&mask16(32), &mask16(32));
    assert_eq!(masked, mask16(32));
    assert_eq!(
        apply_mask4(&[0xc0, 0x00, 0x02, 0x01], &mask4(24)),
        [0xc0, 0x00, 0x02, 0x00]
    );
}

#[test]
fn digits_follow_go_dtoi() {
    assert_eq!(parse_digits("96"), Some(96));
    assert_eq!(parse_digits("096"), Some(96));
    assert_eq!(parse_digits("0032"), Some(32));
    assert_eq!(parse_digits("0"), Some(0));
    assert_eq!(parse_digits(""), None);
    assert_eq!(parse_digits(" +96"), None);
    assert_eq!(parse_digits("+96"), None);
    assert_eq!(parse_digits("-1"), None);
    assert_eq!(parse_digits(" 96"), None);
    assert_eq!(parse_digits("9 6"), None);
    assert_eq!(parse_digits("96\n"), None);
    assert_eq!(parse_digits("1e2"), None);
    assert_eq!(parse_digits("999999999999999999999"), None);
}
