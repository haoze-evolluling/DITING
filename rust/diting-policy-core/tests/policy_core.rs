//! End-to-end checks for the parts that only exist once the tables are wired together:
//! the DTRI subscription trie inside the seven-level walk.
//!
//! The `.dtri` fixtures are the ones the Rust writer produced and byte-compared against the
//! Kotlin/JVM reference (`diting-rule-core/tests/dtri_golden.rs`); the Go engine has its own test
//! that mmaps the same files. Driving the snapshot here proves the reader port resolves every
//! indexable rule in the corpus to the source the corpus declares.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use diting_policy_core::json::RuleSnapshot;
use diting_policy_core::text::go_lower_trim_dot;
use diting_policy_core::Snapshot;

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("diting-rule-core")
        .join("tests")
        .join("fixtures")
}

/// Mirrors the writer's filter: the smallest source per lowercased, dot-trimmed pattern, skipping
/// the rule families a trie cannot hold.
fn expected_sources(corpus: &str) -> HashMap<String, String> {
    let mut expected = HashMap::new();
    for line in corpus.lines() {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        let field = |index: usize, fallback: &str| -> String {
            fields
                .get(index)
                .map(|value| value.to_string())
                .unwrap_or_else(|| fallback.to_string())
        };
        let flag = |index: usize| field(index, "0") == "1";
        let optional_set = |index: usize| {
            let value = field(index, "~");
            !value.is_empty() && value != "~" && value != "="
        };
        let pattern = field(0, "");
        let source = field(1, "");
        if flag(5)
            || pattern.contains('*')
            || optional_set(3)
            || flag(4)
            || flag(7)
            || optional_set(6)
            || optional_set(8)
        {
            continue;
        }
        let pattern = go_lower_trim_dot(&pattern);
        match expected.get(&pattern) {
            Some(previous) if *previous <= source => {}
            _ => {
                expected.insert(pattern, source);
            }
        }
    }
    expected
}

/// Walks the labels from the TLD down and stops at the first indexed suffix, like the reader.
fn lookup<'a>(index: &'a HashMap<String, String>, domain: &str) -> Option<&'a str> {
    let lowered = go_lower_trim_dot(domain);
    let labels: Vec<&str> = lowered.split('.').collect();
    for start in (0..labels.len()).rev() {
        let suffix = labels[start..].join(".");
        if let Some(source) = index.get(&suffix) {
            return Some(source);
        }
    }
    None
}

fn snapshot_with_trie(name: &str) -> (Snapshot, HashMap<String, String>) {
    let root = fixtures();
    let corpus = fs::read_to_string(root.join(format!("{name}.rules.txt"))).expect("corpus");
    let image = fs::read(root.join(format!("{name}.dtri"))).expect("image");
    let path = std::env::temp_dir().join(format!(
        "diting-policy-core-{}-{}.dtri",
        name,
        std::process::id()
    ));
    fs::write(&path, image).expect("write image");
    let json = serde_json::json!({ "blockTriePath": path.to_string_lossy() });
    let request = RuleSnapshot::parse(json.to_string().as_bytes()).expect("parse");
    let snapshot = Snapshot::build(&request);
    (snapshot, expected_sources(&corpus))
}

#[test]
fn dtri_fixtures_resolve_through_the_snapshot() {
    // `basic` and `sources` are pure ASCII, which is what the bloom filter's UTF-16/UTF-8
    // mismatch allows to be exact (see "已知边界" in rust/README.md); `unicode` is checked
    // separately below.
    for name in ["basic", "sources"] {
        let (snapshot, expected) = snapshot_with_trie(name);
        assert!(expected.len() >= 2, "{name}: corpus has no indexable rules");
        for pattern in expected.keys() {
            for query in [
                pattern.clone(),
                pattern.to_uppercase(),
                format!("sub.{pattern}"),
            ] {
                let decision = snapshot.evaluate(&query, "", 1);
                let want = lookup(&expected, &query);
                match want {
                    Some(source) => {
                        assert!(decision.blocked, "{name}: {query} should be blocked");
                        assert_eq!(decision.reason, source, "{name}: {query} source");
                    }
                    None => assert!(!decision.blocked, "{name}: {query} should not match"),
                }
            }
        }
        assert!(
            !snapshot
                .evaluate("not-in-this-fixture.example", "", 1)
                .blocked
        );
    }
}

/// Non-ASCII patterns are a known subset: the writer hashes UTF-16 code units into the bloom while
/// the reader hashes UTF-8 bytes, so a real hit may be filtered out before the trie walk. That is
/// the Go reader's behaviour too; the port must not invent matches the Go engine would miss.
#[test]
fn unicode_fixture_is_a_subset_of_the_expected_sources() {
    let (snapshot, expected) = snapshot_with_trie("unicode");
    let mut hits = 0;
    for pattern in expected.keys() {
        for query in [pattern.clone(), pattern.to_uppercase()] {
            let decision = snapshot.evaluate(&query, "", 1);
            if decision.blocked {
                hits += 1;
                let want = lookup(&expected, &query).expect("hit must be an expected pattern");
                assert_eq!(decision.reason, want, "{query}");
            }
        }
    }
    assert_eq!(
        hits, 0,
        "the bloom filter drops every non-ASCII pattern, as in Go"
    );
}

#[test]
fn disabled_rules_fall_through_to_the_parent_suffix() {
    let (_, expected) = snapshot_with_trie("basic");
    let pattern = expected
        .keys()
        .find(|pattern| pattern.contains('.'))
        .expect("a nested pattern")
        .clone();
    let root = fixtures();
    let image = fs::read(root.join("basic.dtri")).expect("image");
    let path = std::env::temp_dir().join(format!(
        "diting-policy-core-disabled-{}.dtri",
        std::process::id()
    ));
    fs::write(&path, image).expect("write image");
    let json = serde_json::json!({
        "blockTriePath": path.to_string_lossy(),
        "disabledRules": [pattern.to_uppercase()],
    });
    let request = RuleSnapshot::parse(json.to_string().as_bytes()).expect("parse");
    let snapshot = Snapshot::build(&request);
    // The disabled rule is skipped; the walk continues with its parent labels.
    let decision = snapshot.evaluate(&pattern, "", 1);
    let parent_hit = pattern
        .match_indices('.')
        .map(|(dot, _)| &pattern[dot + 1..])
        .any(|suffix| expected.contains_key(suffix));
    assert_eq!(decision.blocked, parent_hit, "got {decision:?}");
}
