//! Replays the fixtures generated from the pre-migration Go implementation
//! (`android/engine/zz_request_fixture_gen_test.go` before it was deleted):
//!
//! | fixture | rows | what it pins |
//! | --- | --- | --- |
//! | `rules.tsv` | 14 | `SetRequestRules` normalization: the kind whitelist and the scheme prefix |
//! | `match.tsv` | 64 | `requestFilterDecision`: 4 rule sets × 16 requests (URL build, port strip, longest prefix, allow ties, fallback host) |

use std::fs;

use diting_request_core::match_rule::decide;
use diting_request_core::rules::{normalize, normalize_all, Rule};

fn fixtures() -> String {
    format!("{}/tests/fixtures", env!("CARGO_MANIFEST_DIR"))
}

fn read(name: &str) -> String {
    let path = format!("{}/{name}", fixtures());
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("{path}: {err}"))
}

fn unquote(field: &str) -> String {
    if !(field.starts_with('"') && field.ends_with('"') && field.len() >= 2) {
        return field.to_string();
    }
    let body = &field[1..field.len() - 1];
    let mut out = String::with_capacity(body.len());
    let mut chars = body.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('"') => out.push('"'),
            Some('\\') => out.push('\\'),
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some(other) => out.push(other),
            None => break,
        }
    }
    out
}

fn rows(name: &str) -> Vec<Vec<String>> {
    read(name)
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| line.split('\t').map(unquote).collect())
        .collect()
}

fn rule_set(fields: &[String], start: usize, count: usize) -> Vec<Rule> {
    let pairs: Vec<(String, String)> = (0..count)
        .map(|index| {
            (
                fields[start + index * 2].clone(),
                fields[start + index * 2 + 1].clone(),
            )
        })
        .collect();
    normalize_all(&pairs)
}

#[test]
fn rule_normalization_matches_the_old_implementation() {
    let mut checked = 0;
    for row in rows("rules.tsv") {
        let (kind, pattern) = (&row[0], &row[1]);
        let kept = normalize(kind, pattern);
        if row[2] == "drop" {
            assert!(kept.is_none(), "{kind} {pattern:?} must be dropped");
        } else {
            let rule = kept.unwrap_or_else(|| panic!("{kind} {pattern:?} must be kept"));
            let allow = row[3] == "allow";
            assert_eq!(rule.allow, allow, "{kind} {pattern:?}");
            assert_eq!(rule.pattern, row[4], "{kind} {pattern:?}");
        }
        checked += 1;
    }
    assert_eq!(checked, 14);
}

#[test]
fn request_decisions_match_the_old_implementation() {
    let mut checked = 0;
    for row in rows("match.tsv") {
        let name = &row[0];
        let count: usize = row[1].parse().unwrap();
        let rules = rule_set(&row, 2, count);
        let tail = 2 + count * 2;
        let (scheme, host, path) = (&row[tail], &row[tail + 1], &row[tail + 2]);
        let decision = decide(&rules, scheme, host, path);
        let expected_matched = row[tail + 3] == "true";
        let expected_blocked = row[tail + 4] == "true";
        assert_eq!(
            decision.matched, expected_matched,
            "{name} {scheme} {host} {path}"
        );
        assert_eq!(
            decision.blocked, expected_blocked,
            "{name} {scheme} {host} {path}"
        );
        assert_eq!(
            decision.pattern,
            row[tail + 5],
            "{name} {scheme} {host} {path}"
        );
        assert_eq!(
            decision.domain_host,
            row[tail + 6],
            "{name} {scheme} {host} {path}"
        );
        checked += 1;
    }
    assert_eq!(checked, 64);
}
