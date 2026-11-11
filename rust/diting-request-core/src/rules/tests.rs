//! The kind/prefix whitelist and the pattern fold.

use super::*;

#[test]
fn patterns_are_trimmed_and_lowered() {
    let rule = normalize("block", "  HTTPS://Ads.Example/Spy  ").expect("kept");
    assert!(!rule.allow);
    assert_eq!(rule.pattern, "https://ads.example/spy");
    let rule = normalize("allow", "https://cdn.example/assets").expect("kept");
    assert!(rule.allow);
}

#[test]
fn the_kind_is_compared_exactly() {
    for kind in ["", "deny", "BLOCK", "block ", " Block"] {
        assert!(normalize(kind, "https://ads.example/x").is_none(), "{kind}");
    }
    assert!(normalize("block", "https://ads.example/x").is_some());
    assert!(normalize("allow", "https://ads.example/x").is_some());
}

#[test]
fn the_pattern_needs_a_scheme_prefix() {
    for pattern in [
        "ftp://ads.example/x",
        "ads.example/x",
        "//ads.example/x",
        "https",
        "",
        "  ",
        "httpx://ads.example/x",
    ] {
        assert!(normalize("block", pattern).is_none(), "{pattern}");
    }
    // The scheme itself is enough: the old check only looked at the prefix.
    assert!(normalize("block", "https://").is_some());
    assert!(normalize("block", "http://").is_some());
}

#[test]
fn an_upper_cased_scheme_is_folded_into_a_valid_prefix() {
    assert!(normalize("block", "HTTP://Ads.Example/x").is_some());
}

#[test]
fn normalize_all_keeps_the_order_and_drops_the_rest() {
    let rules = normalize_all(&[
        ("block".to_string(), "https://a.example/x".to_string()),
        ("deny".to_string(), "https://b.example/x".to_string()),
        ("allow".to_string(), "HTTPS://C.Example/Y".to_string()),
    ]);
    assert_eq!(rules.len(), 2);
    assert_eq!(rules[0].pattern, "https://a.example/x");
    assert_eq!(rules[1].pattern, "https://c.example/y");
    assert!(rules[1].allow);
    assert!(normalize_all(&[]).is_empty());
}
