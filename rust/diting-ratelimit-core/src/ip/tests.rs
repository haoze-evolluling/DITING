use super::*;

#[test]
fn four_and_sixteen_byte_inputs_are_the_only_widths() {
    assert_eq!(
        Addr::from_bytes(&[1, 2, 3, 4]),
        Some(Addr::V4([1, 2, 3, 4]))
    );
    assert_eq!(Addr::from_bytes(&[0; 16]), Some(Addr::V6([0; 16])));
    assert_eq!(Addr::from_bytes(&[]), None);
    assert_eq!(Addr::from_bytes(&[0; 5]), None);
    assert_eq!(Addr::from_bytes(&[0; 15]), None);
}

#[test]
fn a_mapped_address_collapses_to_ipv4() {
    let mut raw = [0u8; 16];
    raw[10] = 0xff;
    raw[11] = 0xff;
    raw[12..].copy_from_slice(&[192, 0, 2, 7]);
    assert_eq!(Addr::from_bytes(&raw), Some(Addr::V4([192, 0, 2, 7])));

    // `::a.b.c.d` (IPv4-compatible, not mapped) stays 16 bytes on both sides.
    let mut compatible = [0u8; 16];
    compatible[12..].copy_from_slice(&[192, 0, 2, 7]);
    assert_eq!(Addr::from_bytes(&compatible), Some(Addr::V6(compatible)));
}

#[test]
fn parse_matches_the_literals_go_accepted() {
    assert_eq!(Addr::parse("192.0.2.7"), Some(Addr::V4([192, 0, 2, 7])));
    assert_eq!(
        Addr::parse("::ffff:192.0.2.7"),
        Some(Addr::V4([192, 0, 2, 7]))
    );
    assert_eq!(
        Addr::parse("2001:db8::1"),
        Addr::from_bytes(&{
            let mut raw = [0u8; 16];
            raw[0] = 0x20;
            raw[1] = 0x01;
            raw[2] = 0x0d;
            raw[3] = 0xb8;
            raw[15] = 1;
            raw
        })
    );
    assert_eq!(
        Addr::parse("::1.2.3.4"),
        Addr::from_bytes(&{
            let mut raw = [0u8; 16];
            raw[12] = 1;
            raw[13] = 2;
            raw[14] = 3;
            raw[15] = 4;
            raw
        })
    );

    for rejected in [
        "01.2.3.4",
        "0x7f.0.0.1",
        "1.2.3",
        "1.2.3.4.5",
        "1.2.3.4 ",
        " 1.2.3.4",
        "::ffff:01.2.3.4",
        "fe80::1%eth0",
        "1::2::3",
        "not-an-ip",
        "",
    ] {
        assert_eq!(
            Addr::parse(rejected),
            None,
            "{rejected:?} should be rejected"
        );
    }
}

#[test]
fn masking_walks_bytes_and_bits() {
    let address = Addr::V4([192, 0, 2, 7]);
    assert_eq!(address.masked(24), Addr::V4([192, 0, 2, 0]));
    assert_eq!(address.masked(25), Addr::V4([192, 0, 2, 0]));
    assert_eq!(address.masked(23), Addr::V4([192, 0, 2, 0]));
    assert_eq!(address.masked(26), Addr::V4([192, 0, 2, 0]));
    assert_eq!(address.masked(32), Addr::V4([192, 0, 2, 7]));
    assert_eq!(address.masked(0), Addr::V4([0, 0, 0, 0]));

    // Non-byte-aligned IPv6: /57 keeps the top bit of byte 7.
    let mut raw = [0u8; 16];
    raw[0] = 0x20;
    raw[1] = 0x01;
    raw[2] = 0x0d;
    raw[3] = 0xb8;
    raw[7] = 0x81;
    raw[8] = 0x01;
    raw[15] = 0x01;
    let address = Addr::V6(raw);
    assert_eq!(
        address.masked(57),
        Addr::V6({
            let mut masked = raw;
            masked[7] = 0x80;
            masked[8] = 0;
            masked[15] = 0;
            masked
        })
    );
    assert_eq!(address.width(), 16);
    assert_eq!(Addr::V4([1, 2, 3, 4]).width(), 4);
}
