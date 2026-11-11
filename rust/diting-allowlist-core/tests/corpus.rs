//! Replays the domain-matching corpus produced by the old Go `domainMatches`.
//!
//! Each row is one allowed set (semicolon-joined, empty for the empty set) and one query, with the
//! boolean the Go implementation returned. The corpus covers exact matches, label-boundary
//! misses, parent entries, one versus two trailing dots, ASCII case, U+0130's Go-specific fold,
//! surrounding spaces (never trimmed by the query walk) and empty queries.

use std::collections::HashSet;

use diting_allowlist_core::domain_matches;

const FIXTURE: &str = include_str!("fixtures/domain_matches.tsv");

#[test]
fn the_domain_corpus_matches_the_old_walk() {
    let mut rows = 0;
    for line in FIXTURE.lines().skip(1) {
        if line.is_empty() {
            continue;
        }
        let mut fields = line.split('\t');
        let allowed_field = fields.next().expect("allowed column");
        let query = fields.next().expect("query column");
        let expected = fields.next().expect("expected column") == "true";
        assert!(fields.next().is_none(), "unexpected extra column in {line}");

        let allowed: HashSet<String> = if allowed_field.is_empty() {
            HashSet::new()
        } else {
            allowed_field.split(';').map(str::to_string).collect()
        };
        assert_eq!(
            domain_matches(&allowed, query),
            expected,
            "allowed={allowed_field:?} query={query:?}"
        );
        rows += 1;
    }
    assert_eq!(rows, 250, "the fixture is the 250-row corpus");
}
