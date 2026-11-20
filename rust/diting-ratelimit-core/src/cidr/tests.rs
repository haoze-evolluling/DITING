use super::*;

fn contains(text: &str, address: &str) -> bool {
    let network = Cidr::parse(text).unwrap_or_else(|| panic!("{text:?} should parse"));
    let address = Addr::parse(address).unwrap_or_else(|| panic!("{address:?} should parse"));
    network.contains(&address)
}

#[test]
fn accepts_what_go_parse_cidr_accepted() {
    for accepted in [
        "10.0.0.0/08",
        "10.0.0.0/8",
        "1.2.3.4/32",
        "1.2.3.4/0",
        "::/0",
        "2001:db8::/32",
        "::ffff:10.0.0.0/120",
        "::1.2.3.4/128",
    ] {
        assert!(
            Cidr::parse(accepted).is_some(),
            "{accepted:?} should be accepted"
        );
    }
    for rejected in [
        "",
        "/8",
        "10.0.0.0/",
        "10.0.0.0/+8",
        "10.0.0.0/ 8",
        "10.0.0.0/8 ",
        " 10.0.0.0/8",
        "10.0.0.0/-1",
        "10.0.0.0/8/8",
        "10.0.0.0/33",
        "01.2.3.4/8",
        "00000000008.0.0.0/8",
        "1.2.3/24",
        "::ffff:10.0.0.0/129",
        "fe80::1%eth0/64",
        "garbage",
    ] {
        assert!(
            Cidr::parse(rejected).is_none(),
            "{rejected:?} should be rejected"
        );
    }
}

#[test]
fn ipv4_networks_compare_masked_and_fold_mapped_clients() {
    assert!(contains("10.0.0.0/8", "10.1.2.3"));
    assert!(contains("10.0.0.0/8", "::ffff:10.1.2.3"));
    assert!(!contains("10.0.0.0/8", "11.1.2.3"));
    assert!(contains("1.2.3.4/31", "1.2.3.4"));
    assert!(contains("1.2.3.4/31", "1.2.3.5"));
    assert!(!contains("1.2.3.4/31", "1.2.3.6"));
}

#[test]
fn ipv6_networks_never_contain_ipv4_literals() {
    assert!(contains("2001:db8::/32", "2001:db8::1"));
    assert!(!contains("2001:db8::/32", "2001:db9::1"));
    assert!(!contains("::/0", "8.8.8.8"));
    assert!(contains("::/0", "2001:db8::1"));
}

#[test]
fn a_mapped_network_collapses_the_way_go_did() {
    assert!(contains("::ffff:10.0.0.0/120", "10.0.0.7"));
    assert!(contains("::ffff:10.0.0.0/120", "::ffff:10.0.0.8"));
    assert!(!contains("::ffff:10.0.0.0/120", "10.0.1.7"));

    assert!(contains("::ffff:10.0.0.0/96", "8.8.8.8"));
    assert!(contains("::ffff:10.0.0.0/96", "::ffff:8.8.4.4"));
    assert!(!contains("::ffff:10.0.0.0/96", "2001:db8::1"));

    assert!(!contains("::ffff:10.0.0.0/95", "10.0.0.7"));
    assert!(!contains("::ffff:10.0.0.0/95", "::ffff:10.0.0.7"));
}
