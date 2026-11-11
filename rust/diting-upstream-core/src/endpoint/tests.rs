use super::*;

#[test]
fn a_bare_host_gets_the_protocol_default_port() {
    assert_eq!(
        split_target("dns.google", TargetProtocol::Plain),
        ("dns.google".to_string(), "53".to_string())
    );
    assert_eq!(
        split_target("dns.google", TargetProtocol::Dot),
        ("dns.google".to_string(), "853".to_string())
    );
    // A bare IPv6 literal has too many colons: SplitHostPort fails, so the whole string stays the
    // host and the default port is used (the Go code did exactly this).
    assert_eq!(
        split_target("2001:db8::1", TargetProtocol::Dot),
        ("2001:db8::1".to_string(), "853".to_string())
    );
}

#[test]
fn an_explicit_port_is_kept_verbatim() {
    assert_eq!(
        split_target("9.9.9.9:5353", TargetProtocol::Plain),
        ("9.9.9.9".to_string(), "5353".to_string())
    );
    assert_eq!(
        split_target("[2001:db8::1]:1053", TargetProtocol::Plain),
        ("2001:db8::1".to_string(), "1053".to_string())
    );
    // Ports are not validated by the transport: the config kernel only checks the shape.
    assert_eq!(
        split_target("dns.google:053", TargetProtocol::Dot),
        ("dns.google".to_string(), "053".to_string())
    );
}

#[test]
fn the_dial_address_prefers_the_bootstrapped_ip() {
    assert_eq!(dial_address("dns.google", "853", ""), "dns.google:853");
    assert_eq!(dial_address("dns.google", "853", "1.2.3.4"), "1.2.3.4:853");
    assert_eq!(
        dial_address("dns.google", "853", "2001:db8::1"),
        "[2001:db8::1]:853"
    );
    assert_eq!(dial_address("2001:db8::1", "53", ""), "[2001:db8::1]:53");
    assert_eq!(dial_address("", "53", ""), ":53");
}
