//! Target classification and the key fold.

use super::*;

fn targets(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| value.to_string()).collect()
}

#[test]
fn first_target_of_each_family_wins() {
    let entry = classify(&targets(&[
        "1.2.3.4",
        "5.6.7.8",
        "::1",
        "::2",
        "a.example",
        "b.example",
    ]))
    .expect("entry");
    assert_eq!(entry.ip4, "1.2.3.4");
    assert_eq!(entry.ip6, "::1");
    assert_eq!(entry.cname, "a.example");
}

#[test]
fn ip_targets_are_stored_in_their_string_form() {
    // A mapped IPv4 literal is an IPv4 answer, in dotted-quad text.
    let entry = classify(&targets(&["::ffff:1.2.3.4"])).expect("entry");
    assert_eq!((entry.ip4.as_str(), entry.ip6.as_str()), ("1.2.3.4", ""));
    // IPv6 text follows `net.IP.String()`, so the compressed form wins.
    let entry = classify(&targets(&["2606:4700:0000::1111"])).expect("entry");
    assert_eq!(entry.ip6, "2606:4700::1111");
}

#[test]
fn names_are_lowered_and_stripped_of_one_dot() {
    let entry = classify(&targets(&["Example.COM."])).expect("entry");
    assert_eq!(entry.cname, "example.com");
    let entry = classify(&targets(&["Example.COM.."])).expect("entry");
    assert_eq!(entry.cname, "example.com.");
    // Anything that is not an IP literal is a CNAME target, spaces inside included.
    let entry = classify(&targets(&["not a host?"])).expect("entry");
    assert_eq!(entry.cname, "not a host?");
}

#[test]
fn blank_targets_are_skipped() {
    let entry = classify(&targets(&["", "  ", "\t", "1.2.3.4"])).expect("entry");
    assert_eq!(entry.ip4, "1.2.3.4");
    assert!(entry.cname.is_empty());
    assert!(classify(&targets(&["", "   "])).is_none());
    assert!(classify(&[]).is_none());
}

#[test]
fn the_key_fold_is_lower_trim_and_one_dot() {
    assert_eq!(normalize_domain("Example.COM"), "example.com");
    assert_eq!(normalize_domain(" example.com "), "example.com");
    assert_eq!(normalize_domain("example.com."), "example.com");
    assert_eq!(normalize_domain("example.com.."), "example.com.");
    assert_eq!(normalize_domain("."), "");
    assert_eq!(normalize_domain("  "), "");
    assert_eq!(normalize_domain("İstanbul.example"), "istanbul.example");
}
