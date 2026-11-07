//! Unit tests for the hostname normalization and the `<link>` tag.

use super::*;

#[test]
fn port_is_dropped_only_when_split_host_port_accepts_it() {
    assert_eq!(normalize_host("Ads.Example.com:443"), "ads.example.com");
    assert_eq!(normalize_host("ads.example.com:80"), "ads.example.com");
    assert_eq!(normalize_host("ads.example.com"), "ads.example.com");
    // No port to find, and `a:b:c` is not an authority `net.SplitHostPort` accepts.
    assert_eq!(normalize_host("a:b:c"), "a:b:c");
    assert_eq!(normalize_host("host:port:extra"), "host:port:extra");
    assert_eq!(normalize_host("x:"), "x");
    assert_eq!(normalize_host(":443"), "");
}

#[test]
fn bracketed_authority_is_cut_at_the_last_bracket() {
    assert_eq!(normalize_host("[::1]:443"), "[::1]");
    assert_eq!(normalize_host("[::1]"), "[::1]");
    // The Go branch cuts at the `]` and returns early, so it never reaches the trailing-dot trim.
    assert_eq!(normalize_host("[::1]."), "[::1]");
    assert_eq!(normalize_host("[fe80::1%25eth0]:443"), "[fe80::1%25eth0]");
}

#[test]
fn one_trailing_dot_is_stripped() {
    assert_eq!(normalize_host("example.com."), "example.com");
    assert_eq!(normalize_host("EXAMPLE.COM.:443"), "example.com");
    assert_eq!(normalize_host(".."), ".");
    assert_eq!(normalize_host("."), "");
}

#[test]
fn surrounding_space_goes_but_inner_space_stays() {
    assert_eq!(normalize_host("  example.com  "), "example.com");
    assert_eq!(normalize_host(" sp ace.com:1"), "sp ace.com");
    assert_eq!(normalize_host("\texample.com\t"), "example.com");
}

#[test]
fn split_host_port_matches_the_go_shape_rules() {
    assert!(split_host_port_ok("host:1"));
    assert!(split_host_port_ok("host:"));
    assert!(split_host_port_ok(":1"));
    assert!(split_host_port_ok("[::1]:443"));
    assert!(split_host_port_ok("[]:1"));
    assert!(!split_host_port_ok("host"));
    assert!(!split_host_port_ok("[::1]"));
    assert!(!split_host_port_ok("a:b:c"));
    assert!(!split_host_port_ok("[abc]:1:2"));
    assert!(!split_host_port_ok("[abc"));
    // A `]` in the host part is what `SplitHostPort` calls an unexpected bracket; in the port it is
    // just part of an unvalidated port string.
    assert!(!split_host_port_ok("]:1"));
    assert!(!split_host_port_ok("host]:1"));
    assert!(split_host_port_ok("host:1]"));
    assert!(!split_host_port_ok(""));
}

#[test]
fn query_escape_keeps_the_unreserved_set_and_plus_for_space() {
    assert_eq!(query_escape("ads.example.com"), "ads.example.com");
    assert_eq!(query_escape("sp ace.com"), "sp+ace.com");
    assert_eq!(query_escape("[::1]"), "%5B%3A%3A1%5D");
    assert_eq!(query_escape("h%25ost"), "h%2525ost");
    assert_eq!(query_escape("-_.~"), "-_.~");
    assert_eq!(query_escape("例え"), "%E4%BE%8B%E3%81%88");
}

#[test]
fn link_tag_carries_the_normalized_host() {
    assert_eq!(
        link_tag("Ads.Example.com:443", "local.pwhs.app"),
        r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h=ads.example.com">"#
    );
    // An empty host means there is no query at all, not `?h=`.
    assert_eq!(
        link_tag("", "local.pwhs.app"),
        r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css">"#
    );
    assert_eq!(
        link_tag(".", "local.pwhs.app"),
        r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css">"#
    );
}
