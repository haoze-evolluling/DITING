//! Byte-level parity with the Kotlin DTRI writer.
//!
//! The `.dtri` fixtures are produced by `rust/tools/dtri-reference/DTRIReference.java`, a desktop
//! port of `MappedSubscriptionRuleIndex.compile`; the Rust writer must emit exactly the same bytes.
//! Regenerate with:
//!
//! ```bash
//! java rust/tools/dtri-reference/DTRIReference.java \
//!     rust/diting-rule-core/tests/fixtures/basic.rules.txt \
//!     rust/diting-rule-core/tests/fixtures/basic.dtri
//! ```

use std::fs;
use std::path::PathBuf;

use diting_rule_core::dtri::{compile, compile_packed, Rule, MAGIC, VERSION};

const FIXTURES: [&str; 3] = ["basic", "sources", "unicode"];

struct OwnedRule {
    pattern: String,
    source: String,
    app_scope: Option<String>,
    app_inverted: bool,
    is_wildcard: bool,
    denyallow: Option<String>,
    is_regex: bool,
    dns_type: Option<String>,
}

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

/// Same corpus format as the Java reference: tab separated, `~` is null and `=` is "".
fn parse_corpus(text: &str) -> Vec<OwnedRule> {
    text.lines()
        .filter(|line| !line.is_empty())
        .map(|line| {
            let fields: Vec<&str> = line.split('\t').collect();
            let field = |index: usize| fields.get(index).copied().unwrap_or("");
            let optional = |index: usize| match fields.get(index).copied().unwrap_or("~") {
                "~" => None,
                "=" => Some(String::new()),
                value => Some(value.to_string()),
            };
            let flag = |index: usize| matches!(field(index), "1" | "true");
            OwnedRule {
                pattern: field(0).to_string(),
                source: field(1).to_string(),
                app_scope: optional(3),
                app_inverted: flag(4),
                is_wildcard: flag(5),
                denyallow: optional(6),
                is_regex: flag(7),
                dns_type: optional(8),
            }
        })
        .collect()
}

#[test]
fn rust_writer_matches_the_kotlin_reference_bytes() {
    for name in FIXTURES {
        let corpus = fs::read_to_string(fixture(&format!("{name}.rules.txt")))
            .unwrap_or_else(|error| panic!("{name}.rules.txt: {error}"));
        let expected = fs::read(fixture(&format!("{name}.dtri")))
            .unwrap_or_else(|error| panic!("{name}.dtri: {error}"));
        let owned = parse_corpus(&corpus);
        assert!(owned.len() > 1, "{name}: corpus is empty");
        let rules: Vec<Rule<'_>> = owned
            .iter()
            .map(|rule| Rule {
                pattern: &rule.pattern,
                source: &rule.source,
                app_scope: rule.app_scope.as_deref(),
                app_inverted: rule.app_inverted,
                is_wildcard: rule.is_wildcard,
                denyallow: rule.denyallow.as_deref(),
                is_regex: rule.is_regex,
                dns_type: rule.dns_type.as_deref(),
            })
            .collect();
        let actual = compile(&rules);
        assert_eq!(actual.len(), expected.len(), "{name}: image length");
        assert_eq!(actual, expected, "{name}: image bytes");
    }
}

#[test]
fn fixtures_carry_the_expected_header() {
    for name in FIXTURES {
        let image = fs::read(fixture(&format!("{name}.dtri"))).unwrap();
        let read = |offset: usize| {
            u32::from_be_bytes([
                image[offset],
                image[offset + 1],
                image[offset + 2],
                image[offset + 3],
            ])
        };
        assert_eq!(read(0), MAGIC, "{name}: magic");
        assert_eq!(read(4), VERSION, "{name}: version");
        assert!(read(8) > 1, "{name}: nodes");
        assert!(read(20) >= 64, "{name}: bloom bits");
    }
}

#[test]
fn packed_payload_matches_the_kotlin_wire_format() {
    for name in FIXTURES {
        let packed = fs::read(fixture(&format!("{name}.pack")))
            .unwrap_or_else(|error| panic!("{name}.pack: {error}"));
        let expected = fs::read(fixture(&format!("{name}.dtri"))).unwrap();
        let compiled = compile_packed(&packed).expect("packed payload decodes");
        assert_eq!(compiled, expected, "{name}: packed payload");
    }
}
