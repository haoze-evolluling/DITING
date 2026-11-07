//! The decision table: URL build, port stripping, longest prefix, allow ties.

use super::*;
use crate::rules::normalize_all;

fn rule_set(pairs: &[(&str, &str)]) -> Vec<Rule> {
    normalize_all(
        &pairs
            .iter()
            .map(|(kind, pattern)| (kind.to_string(), pattern.to_string()))
            .collect::<Vec<_>>(),
    )
}

fn ads() -> Vec<Rule> {
    rule_set(&[
        ("block", "https://ads.example/spy"),
        ("allow", "https://ads.example/spy/allowed"),
    ])
}

#[test]
fn a_block_rule_matches_its_prefix() {
    let decision = decide(&ads(), "https", "ads.example", "/spy");
    assert!(decision.matched && decision.blocked);
    assert_eq!(decision.pattern, "https://ads.example/spy");
    assert_eq!(decision.domain_host, "ads.example");
}

#[test]
fn a_longer_allow_overrides_the_block() {
    let decision = decide(&ads(), "https", "ads.example", "/spy/allowed/deeper");
    assert!(decision.matched && !decision.blocked);
    assert_eq!(decision.pattern, "https://ads.example/spy/allowed");
}

#[test]
fn an_allow_wins_a_tie() {
    let rules = rule_set(&[
        ("block", "https://tie.example/x"),
        ("allow", "https://tie.example/x"),
    ]);
    let decision = decide(&rules, "https", "tie.example", "/x");
    assert!(decision.matched && !decision.blocked);
    // The first rule of that length keeps the slot; only the verdict changes.
    assert_eq!(decision.pattern, "https://tie.example/x");
}

#[test]
fn nothing_matched_reports_the_fallback_host() {
    let decision = decide(&ads(), "https", "other.example", "/spy");
    assert!(!decision.matched && !decision.blocked);
    assert_eq!(decision.pattern, "");
    assert_eq!(decision.domain_host, "other.example");
    // No rules at all behaves the same way.
    let decision = decide(&[], "https", "other.example", "/");
    assert!(!decision.matched && !decision.blocked);
}

#[test]
fn the_default_port_is_stripped_for_the_matching_scheme_only() {
    // `https` + `:443` folds away, so the pattern still matches.
    let decision = decide(&ads(), "https", "ads.example:443", "/spy");
    assert!(decision.matched && decision.blocked);
    // `http` + `:443` is not a default port for the scheme, so the host keeps it.
    let decision = decide(&ads(), "http", "ads.example:443", "/spy");
    assert!(!decision.matched);
    // An upper-case scheme never takes the default-port branch (the comparison is exact).
    let decision = decide(&ads(), "HTTPS", "ads.example:443", "/spy");
    assert!(!decision.matched);
    // ... and the built URL is lower-cased, so the same request without a port still matches.
    let decision = decide(&ads(), "HTTPS", "ads.example", "/spy");
    assert!(decision.matched && decision.blocked);
}

#[test]
fn host_and_path_are_folded() {
    let decision = decide(&ads(), "https", " A.Example ", "/y");
    assert_eq!(decision.domain_host, "a.example");
    let rules = rule_set(&[("allow", "https://a.example")]);
    // The path is lower-cased as part of the URL, and an empty path becomes `/`.
    assert!(decide(&rules, "https", "A.Example", "/Y").matched);
    assert!(decide(&rules, "https", "a.example", "").matched);
}

#[test]
fn the_fallback_host_always_loses_its_port() {
    let decision = decide(&[], "https", "a.example:8443", "/x");
    assert_eq!(decision.domain_host, "a.example");
    let decision = decide(&[], "https", "[::1]:443", "/x");
    assert_eq!(decision.domain_host, "::1");
    // A host that does not split stays as it is.
    let decision = decide(&[], "https", "a.example", "/x");
    assert_eq!(decision.domain_host, "a.example");
}
