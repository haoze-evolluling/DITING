//! Per-line entry point and whole-document aggregation; a port of `rule_parser.dart`.
//!
//! `parse_document` collects `$badfilter` keys while it parses instead of scanning the text twice,
//! which is what the Dart original did. Removal happens after every line is classified, so the two
//! orders produce the same rules and the same counters.

use std::collections::HashMap;

use crate::fast_hash::FxBuildHasher;

use crate::hosts::{parse_dnsmasq_line, parse_hosts_line_detailed};
use crate::keys::{allow_key_of, block_key_of, rewrite_key_of, url_key};
use crate::line::{is_cosmetic_rule_line, parse_line_without_state};
use crate::models::{CategorizedLine, CategorizedRules, ParsedCosmeticRule, ParsedRule};

/// Parses one line without cross-line state (for streaming imports).
pub fn parse_categorized_line(original_line: &str) -> CategorizedLine {
    let line = original_line.trim().trim_start_matches('\u{FEFF}');
    if line.is_empty()
        || line.starts_with('!')
        || (line.starts_with('#') && !is_cosmetic_rule_line(line))
        || (line.starts_with('[') && line.ends_with(']'))
    {
        return CategorizedLine::ignored();
    }

    if line.starts_with("address=/") || line.starts_with("server=/") {
        return parse_dnsmasq_line(line, original_line);
    }

    if let Some(hosts) = parse_hosts_line_detailed(line, original_line) {
        return hosts;
    }

    let allow = line.starts_with("@@");
    parse_line_without_state(line, original_line, allow)
}

/// Insertion-ordered dedupe: first occurrence wins, later ones count as duplicates.
///
/// The map owns the keys and the vector only holds values, so inserting a rule allocates the key
/// once. Removing a `$badfilter` key leaves a hole that [`Dedupe::into_values`] skips, which keeps
/// the remaining rules in their original order without rebuilding the index.
struct Dedupe<T> {
    index: HashMap<String, usize, FxBuildHasher>,
    entries: Vec<Option<T>>,
}

impl<T> Default for Dedupe<T> {
    fn default() -> Self {
        Self {
            index: HashMap::default(),
            entries: Vec::new(),
        }
    }
}

impl<T> Dedupe<T> {
    /// Returns 1 when the key was already present, 0 on insert, to accumulate `duplicateCount`.
    fn add(&mut self, key: String, value: T) -> u32 {
        match self.index.entry(key) {
            std::collections::hash_map::Entry::Occupied(_) => 1,
            std::collections::hash_map::Entry::Vacant(slot) => {
                slot.insert(self.entries.len());
                self.entries.push(Some(value));
                0
            }
        }
    }

    fn remove_keys(&mut self, keys: &std::collections::HashSet<String>) -> u32 {
        let mut removed = 0;
        for key in keys {
            if let Some(position) = self.index.remove(key) {
                if self.entries[position].take().is_some() {
                    removed += 1;
                }
            }
        }
        removed
    }

    fn into_values(self) -> Vec<T> {
        self.entries.into_iter().flatten().collect()
    }
}

pub fn parse_document(text: &str) -> CategorizedRules {
    let mut block_rules: Dedupe<ParsedRule> = Dedupe::default();
    let mut allow_rules: Dedupe<ParsedRule> = Dedupe::default();
    let mut rewrite_rules: Dedupe<crate::models::ParsedRewriteRule> = Dedupe::default();
    let mut url_block_rules: Dedupe<crate::models::ParsedUrlRule> = Dedupe::default();
    let mut url_allow_rules: Dedupe<crate::models::ParsedUrlRule> = Dedupe::default();
    let mut cosmetic_rules: Dedupe<ParsedCosmeticRule> = Dedupe::default();
    let mut badfilter_keys = std::collections::HashSet::new();

    let mut duplicates = 0u32;
    let mut invalid = 0u32;
    let mut unsupported = 0u32;
    let mut ignored = 0u32;
    let mut total = 0u32;

    for original_line in text.split('\n') {
        total += 1;
        let line_result = parse_categorized_line(original_line);
        invalid += line_result.invalid_count;
        unsupported += line_result.unsupported_count;
        ignored += line_result.ignored_count;
        badfilter_keys.extend(line_result.badfilter_keys);

        for rule in line_result.block_rules {
            let key = block_key_of(&rule);
            duplicates += block_rules.add(key, rule);
        }
        for rule in line_result.allow_rules {
            let key = allow_key_of(&rule);
            duplicates += allow_rules.add(key, rule);
        }
        for rule in line_result.rewrite_rules {
            let key = rewrite_key_of(&rule);
            duplicates += rewrite_rules.add(key, rule);
        }
        for rule in line_result.url_block_rules {
            let key = url_key("url_block", &rule.pattern, rule.app_scope.as_deref());
            duplicates += url_block_rules.add(key, rule);
        }
        for rule in line_result.url_allow_rules {
            let key = url_key("url_allow", &rule.pattern, rule.app_scope.as_deref());
            duplicates += url_allow_rules.add(key, rule);
        }
        for rule in line_result.cosmetic_rules {
            let key = format!(
                "cosmetic:{}:{}:{}",
                rule.domain, rule.selector, rule.is_exception
            );
            duplicates += cosmetic_rules.add(key, rule);
        }
    }

    let mut badfiltered = 0u32;
    if !badfilter_keys.is_empty() {
        badfiltered += block_rules.remove_keys(&badfilter_keys);
        badfiltered += allow_rules.remove_keys(&badfilter_keys);
        badfiltered += rewrite_rules.remove_keys(&badfilter_keys);
    }

    CategorizedRules {
        block_rules: block_rules.into_values(),
        allow_rules: allow_rules.into_values(),
        rewrite_rules: rewrite_rules.into_values(),
        url_block_rules: url_block_rules.into_values(),
        url_allow_rules: url_allow_rules.into_values(),
        cosmetic_rules: cosmetic_rules.into_values(),
        duplicate_count: duplicates,
        invalid_count: invalid,
        unsupported_count: unsupported,
        ignored_count: ignored,
        badfiltered_count: badfiltered,
        total_lines: total,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{REWRITE_IPV4, REWRITE_IPV6};

    fn patterns(rules: &[ParsedRule]) -> Vec<&str> {
        rules.iter().map(|rule| rule.pattern.as_str()).collect()
    }

    #[test]
    fn ignores_comments_and_blanks() {
        let parsed = parse_document("! comment\n\n# comment\n[Adblock Plus 2.0]\n");
        assert!(parsed.is_empty());
        assert_eq!(parsed.ignored_count, 5);
        assert_eq!(parsed.total_lines, 5);
    }

    #[test]
    fn parses_domain_and_allow_rules() {
        let parsed = parse_document("||example.com^\n@@||safe.example.com^\n");
        assert_eq!(patterns(&parsed.block_rules), ["example.com"]);
        assert_eq!(patterns(&parsed.allow_rules), ["safe.example.com"]);
    }

    #[test]
    fn applies_app_scope_and_important() {
        let parsed = parse_document("||ads.net^$app=com.app1|com.app2,important\n");
        let rule = &parsed.block_rules[0];
        assert_eq!(rule.pattern, "ads.net");
        assert!(rule.important);
        assert_eq!(rule.app_scope.as_deref(), Some("com.app1|com.app2"));
        assert!(!rule.app_inverted);
    }

    #[test]
    fn inverts_app_scope() {
        let parsed = parse_document("||tracker.com^$app=~com.android.chrome\n");
        let rule = &parsed.block_rules[0];
        assert_eq!(rule.app_scope.as_deref(), Some("com.android.chrome"));
        assert!(rule.app_inverted);
    }

    #[test]
    fn parses_dnsrewrite_targets() {
        // `::1` is a sinkhole address, so that line becomes a block rule, not a rewrite.
        let parsed = parse_document(
            "||a.example.com^$dnsrewrite=1.2.3.4\n||b.example.com^$dnsrewrite=::2\n||c.example.com^$dnsrewrite=other.example.com\n||d.example.com^$dnsrewrite=NXDOMAIN",
        );
        assert_eq!(parsed.rewrite_rules.len(), 3);
        assert_eq!(parsed.rewrite_rules[0].target_type, REWRITE_IPV4);
        assert_eq!(parsed.rewrite_rules[1].target_type, REWRITE_IPV6);
        assert_eq!(parsed.rewrite_rules[2].target_type, "CNAME");
        assert_eq!(patterns(&parsed.block_rules), ["d.example.com"]);
    }

    #[test]
    fn drops_badfiltered_rules() {
        let parsed = parse_document("||ads.example.com^\n||ads.example.com^$badfilter\n");
        assert!(parsed.block_rules.is_empty());
        assert_eq!(parsed.badfiltered_count, 1);
    }

    #[test]
    fn counts_duplicates() {
        let parsed = parse_document("||a.example.com^\n||a.example.com^\n");
        assert_eq!(parsed.block_rules.len(), 1);
        assert_eq!(parsed.duplicate_count, 1);
    }

    #[test]
    fn rejects_unsupported_modifiers() {
        let parsed = parse_document("||a.example.com^$foo=bar\n");
        assert!(parsed.is_empty());
        assert_eq!(parsed.unsupported_count, 1);
    }

    #[test]
    fn classifies_web_only_modifiers_as_ignored() {
        let parsed = parse_document("||a.example.com^$third-party");
        assert!(parsed.is_empty());
        assert_eq!(parsed.ignored_count, 1);
    }

    #[test]
    fn parses_cosmetic_and_url_rules() {
        let parsed = parse_document(
            "example.org##.ad-banner\n||ads.example.com/path^\n/^ad[0-9]+\\.example\\.com$/\n",
        );
        assert_eq!(parsed.cosmetic_rules.len(), 1);
        assert_eq!(parsed.cosmetic_rules[0].selector, ".ad-banner");
        assert_eq!(parsed.url_block_rules.len(), 1);
        assert_eq!(parsed.url_block_rules[0].pattern, "ads.example.com/path");
        assert_eq!(
            patterns(&parsed.block_rules),
            ["^ad[0-9]+\\.example\\.com$"]
        );
        assert!(parsed.block_rules[0].is_regex);
    }

    #[test]
    fn parses_hosts_and_dnsmasq_documents() {
        let parsed = parse_document(
            "0.0.0.0 tracker.example.net\n1.2.3.4 rewrite.example.net\naddress=/blocked.example.net/\n",
        );
        assert_eq!(
            patterns(&parsed.block_rules),
            ["tracker.example.net", "blocked.example.net"]
        );
        assert_eq!(parsed.rewrite_rules.len(), 1);
        assert_eq!(parsed.rewrite_rules[0].pattern, "rewrite.example.net");
    }
}
