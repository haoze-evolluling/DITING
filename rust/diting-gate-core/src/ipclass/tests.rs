use super::*;

fn v4(a: u8, b: u8, c: u8, d: u8) -> [u8; 4] {
    [a, b, c, d]
}

#[test]
fn ipv4_classes_match_the_go_predicates() {
    assert!(is_loopback_or_internal(&v4(127, 0, 0, 1)));
    assert!(is_loopback_or_internal(&v4(10, 1, 2, 3)));
    assert!(is_loopback_or_internal(&v4(172, 16, 0, 1)));
    assert!(is_loopback_or_internal(&v4(172, 31, 255, 255)));
    assert!(!is_loopback_or_internal(&v4(172, 32, 0, 1)));
    assert!(is_loopback_or_internal(&v4(192, 168, 1, 1)));
    assert!(is_loopback_or_internal(&v4(169, 254, 1, 1)));
    assert!(is_loopback_or_internal(&v4(0, 0, 0, 0)));
    assert!(!is_loopback_or_internal(&v4(8, 8, 8, 8)));
    assert!(!is_private_ip(&v4(8, 8, 8, 8)));
}

#[test]
fn ipv4_mapped_addresses_fold() {
    let mut mapped = [0u8; 16];
    mapped[10] = 0xff;
    mapped[11] = 0xff;
    mapped[12..].copy_from_slice(&v4(10, 0, 0, 7));
    assert!(is_private_ip(&mapped));
    assert!(is_loopback_or_internal(&mapped));

    let mut loopback = [0u8; 16];
    loopback[10] = 0xff;
    loopback[11] = 0xff;
    loopback[12..].copy_from_slice(&v4(127, 0, 0, 1));
    assert!(is_loopback_or_internal(&loopback));
}

#[test]
fn ipv6_classes() {
    assert!(is_unspecified(&[0u8; 16]));
    let mut loopback = [0u8; 16];
    loopback[15] = 1;
    assert!(is_loopback_or_internal(&loopback));
    assert!(!is_private_ip(&loopback));

    let link_local = [0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1];
    assert!(is_link_local_unicast(&link_local));
    assert!(is_loopback_or_internal(&link_local));

    let global = [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1];
    assert!(!is_loopback_or_internal(&global));
}

#[test]
fn tls_client_ports() {
    for port in [443, 465, 993, 8443] {
        assert!(is_tls_client_port(port));
    }
    for port in [80, 53, 8080, 0] {
        assert!(!is_tls_client_port(port));
    }
}
