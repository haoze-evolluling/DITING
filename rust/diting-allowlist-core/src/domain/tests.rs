use super::*;

fn set(domains: &[&str]) -> HashSet<String> {
    domains.iter().map(|domain| (*domain).to_string()).collect()
}

#[test]
fn config_entries_are_trimmed_lowered_and_stripped_once() {
    assert_eq!(
        normalize_entry(" Example.COM. ").as_deref(),
        Some("example.com")
    );
    assert_eq!(
        normalize_entry("example.com..").as_deref(),
        Some("example.com.")
    );
    assert_eq!(
        normalize_entry("\texample.com\n").as_deref(),
        Some("example.com")
    );
    assert_eq!(normalize_entry("   ").as_deref(), None);
    assert_eq!(normalize_entry(".").as_deref(), None);
    assert_eq!(normalize_entry("").as_deref(), None);
    // Go's Unicode simple case mapping folds U+0130 to `i`, Rust's full mapping would not.
    assert_eq!(
        normalize_entry("İstanbul.example").as_deref(),
        Some("istanbul.example")
    );
}

#[test]
fn query_names_are_lowered_but_never_trimmed() {
    assert_eq!(normalize_query_name("Example.COM."), "example.com");
    assert_eq!(normalize_query_name("example.com.."), "example.com.");
    assert_eq!(normalize_query_name(" example.com "), " example.com ");
    assert_eq!(normalize_query_name(""), "");
    assert_eq!(normalize_query_name("İ.example."), "i.example");
}

#[test]
fn the_suffix_walk_stops_at_label_boundaries() {
    let allowed = set(&["example.com"]);
    assert!(domain_matches(&allowed, "example.com"));
    assert!(domain_matches(&allowed, "www.example.com"));
    assert!(domain_matches(&allowed, "a.b.example.com"));
    assert!(domain_matches(&allowed, "EXAMPLE.COM."));
    assert!(!domain_matches(&allowed, "notexample.com"));
    assert!(!domain_matches(&allowed, "example.com.evil"));
    assert!(!domain_matches(&allowed, ""));
}

#[test]
fn only_one_trailing_dot_is_stripped_from_the_query() {
    let allowed = set(&["example.com."]);
    // The set holds one trailing dot; the query loses exactly one, so the first candidate matches.
    assert!(domain_matches(&allowed, "example.com.."));
    // A single trailing dot in the query leaves "example.com", which is not in the set.
    assert!(!domain_matches(&allowed, "example.com."));
}

#[test]
fn a_parent_entry_covers_every_child() {
    let allowed = set(&["com"]);
    assert!(domain_matches(&allowed, "example.com"));
    assert!(domain_matches(&allowed, "a.b.example.com"));
    assert!(!domain_matches(&allowed, "comm"));
    // The query drops its trailing dot, so it becomes the parent entry itself.
    assert!(domain_matches(&allowed, "com."));
}

#[test]
fn an_empty_set_never_matches() {
    assert!(!domain_matches(&HashSet::new(), "example.com"));
    // Even a set containing "" cannot match: the walk stops before testing an empty candidate.
    assert!(!domain_matches(&set(&[""]), "example.com"));
}
