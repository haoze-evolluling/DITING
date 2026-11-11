//! Endpoint validation, pinned case by case against the old `validateDNSProvider`.

use super::*;

#[test]
fn plain_and_dot_take_host_port() {
    for (protocol, server) in [
        ("PLAIN", "1.1.1.1:53"),
        ("plain", "1.1.1.1:53"),
        ("PLAIN", "[2606:4700:4700::1111]:53"),
        ("DOT", "dns.google:853"),
        // The old check only looks at the shape: a trailing colon, a leading zero and a port
        // above 65535 all passed.
        ("PLAIN", "1.1.1.1:"),
        ("PLAIN", "1.1.1.1:053"),
        ("PLAIN", "1.1.1.1:65536"),
        ("DOT", "host name:853"),
    ] {
        assert!(
            validate_provider(protocol, server, "").is_ok(),
            "{protocol} {server}"
        );
    }
}

#[test]
fn plain_and_dot_reject_bad_addresses() {
    for (server, expected) in [
        (
            "1.1.1.1",
            "invalid PLAIN endpoint \"1.1.1.1\": address 1.1.1.1: missing port in address",
        ),
        ("", "invalid PLAIN endpoint \"\": missing port in address"),
        (
            "[::1]",
            "invalid PLAIN endpoint \"[::1]\": address [::1]: missing port in address",
        ),
        (
            "::1:53",
            "invalid PLAIN endpoint \"::1:53\": address ::1:53: too many colons in address",
        ),
        (
            ":53",
            "invalid PLAIN endpoint \":53\": host is not a valid IP literal",
        ),
        (
            "[1.1.1.1:53]:53",
            "invalid PLAIN endpoint \"[1.1.1.1:53]:53\": host is not a valid IP literal",
        ),
    ] {
        assert_eq!(
            validate_provider("PLAIN", server, "").unwrap_err(),
            expected,
            "{server}"
        );
    }
    // The mode name in the error is the upper-cased protocol.
    assert!(validate_provider("dot", "1.1.1.1", "")
        .unwrap_err()
        .starts_with("invalid DOT endpoint"));
}

#[test]
fn doh_requires_an_https_url_with_a_host() {
    for url in [
        "https://dns.google/dns-query",
        "https://dns.google:443/dns-query?x=1",
        "HTTPS://dns.google/x",
        "https://user:pw@dns.google/x",
        "https://dns.google:/x",
        "https://dns.google/x#frag",
        "https://[::1]:443/x",
        "https://例子.example/x",
    ] {
        assert!(validate_provider("DOH", "", url).is_ok(), "{url}");
    }
    for url in [
        "http://dns.google/dns-query",
        "https:///dns-query",
        "https:opaque",
        "dns.google",
        "",
        "https://dns.google:abc/x",
        "https://dns google/x",
        "https://dns%2egoogle/x",
        " https://dns.google/x",
        "//dns.google/x",
    ] {
        assert_eq!(
            validate_provider("DOH", "", url).unwrap_err(),
            format!("invalid DOH URL \"{url}\""),
            "{url}"
        );
    }
}

#[test]
fn doq_accepts_the_loose_url_form() {
    for url in [
        "quic://dns.adguard.com:8853",
        "https://dns.adguard.com/dns-query",
        "doq://[2606:4700::1111]:853",
        "dns.adguard.com",
    ] {
        assert!(validate_provider("DOQ", "", url).is_ok(), "{url}");
    }
    for url in ["", "quic://", "doq:///path"] {
        assert_eq!(
            validate_provider("DOQ", "", url).unwrap_err(),
            format!("invalid DOQ URL \"{url}\""),
            "{url}"
        );
    }
}

#[test]
fn unknown_protocols_are_rejected_before_the_endpoint() {
    assert_eq!(
        validate_provider("HYPER", "1.1.1.1:53", "").unwrap_err(),
        "unsupported protocol \"HYPER\""
    );
    assert_eq!(
        validate_provider("hyper", "1.1.1.1:53", "").unwrap_err(),
        "unsupported protocol \"HYPER\""
    );
}

#[test]
fn doq_url_splits_like_the_old_helper() {
    for (url, host, port) in [
        ("quic://dns.adguard.com:8853", "dns.adguard.com", "8853"),
        (
            "https://dns.adguard.com/dns-query",
            "dns.adguard.com",
            "853",
        ),
        ("doq://dns.adguard.com", "dns.adguard.com", "853"),
        ("dns.adguard.com", "dns.adguard.com", "853"),
        ("dns.adguard.com:8853", "dns.adguard.com", "8853"),
        ("quic://[2606:4700::1111]:853", "2606:4700::1111", "853"),
        // A bracketed host without a port does not split, so the whole text stays the host.
        ("[2606:4700::1111]", "[2606:4700::1111]", "853"),
        (
            "quic://dns.adguard.com:8853/path?x=1",
            "dns.adguard.com",
            "8853",
        ),
        ("doq://::1", "::1", "853"),
        ("quic://", "", "853"),
        ("", "", "853"),
    ] {
        assert_eq!(
            parse_doq_url(url),
            (host.to_string(), port.to_string()),
            "{url}"
        );
    }
}

#[test]
fn request_uri_keeps_the_lower_cased_scheme_and_host() {
    let uri = parse_request_uri("HTTPS://User:pw@dns.google:443/x?q=1").expect("parses");
    assert_eq!(uri.scheme, "https");
    assert_eq!(uri.host, "dns.google:443");
    let opaque = parse_request_uri("https:opaque").expect("parses");
    assert_eq!(opaque.scheme, "https");
    assert!(opaque.host.is_empty());
    assert!(parse_request_uri("dns.google").is_none());
    assert!(parse_request_uri("https://dns.google/x\n").is_none());
}
