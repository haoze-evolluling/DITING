//! `isSensitiveHost` and `isIPAddress` pinned against the Go code they replaced.
//!
//! `tests/fixtures/sensitive_host.tsv` holds one host per row with the Go verdicts for both
//! predicates; the explicit cases below keep the interesting branches readable next to the port.

use super::*;

const SENSITIVE_HOSTS: &str = include_str!("../../tests/fixtures/sensitive_host.tsv");

#[test]
fn sensitive_and_address_checks_agree_with_go() {
    let mut rows = 0;
    for line in SENSITIVE_HOSTS.lines() {
        let mut fields = line.split('\t').map(crate::fixture::unescape);
        let host = fields.next().expect("host column");
        let sensitive = fields.next().expect("sensitive column");
        let address = fields.next().expect("address column");
        assert_eq!(
            is_sensitive_host(&host),
            sensitive == "true",
            "isSensitiveHost({host:?})"
        );
        assert_eq!(
            is_ip_address(&host),
            address == "true",
            "isIPAddress({host:?})"
        );
        rows += 1;
    }
    assert_eq!(rows, 73, "the fixture is incomplete");
}

#[test]
fn whole_labels_are_enough() {
    assert!(is_sensitive_host("bank.example.com"));
    assert!(is_sensitive_host("pay.example.com"));
    assert!(is_sensitive_host("login.example.com"));
    assert!(is_sensitive_host("gov.cn"));
    assert!(!is_sensitive_host("nobankhere.com"));
    assert!(!is_sensitive_host("example.com"));
    // The caller lowercases before asking, and so did the Go code.
    assert!(!is_sensitive_host("BANK.example.com"));
}

#[test]
fn dash_and_underscore_split_labels_into_tokens() {
    assert!(is_sensitive_host("online-payment.example.com"));
    assert!(is_sensitive_host("secure_login.example.com"));
    assert!(!is_sensitive_host("on-line.example.com"));
}

#[test]
fn bank_needs_six_bytes_of_label() {
    // `bank1` is five bytes: neither prefix nor suffix counts.
    assert!(!is_sensitive_host("bank1.example.com"));
    assert!(is_sensitive_host("mybank.com"));
    assert!(is_sensitive_host("bankofchina.com"));
}

#[test]
fn payment_brands_are_matched_even_inside_a_label() {
    assert!(is_sensitive_host("paypal.com"));
    assert!(is_sensitive_host("myalipay.com"));
    assert!(is_sensitive_host("wechatpay.cn"));
    assert!(is_sensitive_host("applepay.example"));
    assert!(!is_sensitive_host("paypoint.com"));
}

#[test]
fn ip_addresses_are_the_go_predicate() {
    assert!(is_ip_address("1.2.3.4"));
    // Deliberate quirk: only digits and dots are checked, so this is "an address" too.
    assert!(is_ip_address("1.2.3.4.5"));
    assert!(is_ip_address("::1"));
    assert!(is_ip_address("[::1]"));
    assert!(!is_ip_address("example.com"));
    assert!(!is_ip_address(""));
    // Dots alone are still "digits and dots", which the Go predicate accepted.
    assert!(is_ip_address("1.2.3."));
    assert!(!is_ip_address("1.2.3.a"));
}
