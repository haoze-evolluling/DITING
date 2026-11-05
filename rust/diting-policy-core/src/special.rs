//! `specialRule`: the rules that carry an app scope, a `dnsType` filter, a `denyallow` exception
//! list or a regex body (`policy_snapshot.go` / `parseSpecialRule` in `policy_engine.go`).
//!
//! Everything here is a field-for-field port, including the order of the four checks in
//! [`SpecialRule::matches`], because the first failing level decides the verdict.

use std::collections::HashMap;

use regex::Regex;

use crate::glob::WildcardMatcher;
use crate::json;
use crate::regex_go;
use crate::text::{go_lower, go_lower_trim_dot, go_trim_space};

/// `specialRule`.
pub struct SpecialRule {
    /// Reason reported when the rule hits: the lowered pattern, or the raw one for regex rules.
    pub pattern: String,
    pub source: String,
    pub important: bool,
    pub is_allow: bool,
    pub app_scope: HashMap<String, ()>,
    pub app_inverted: bool,
    pub denyallow: Vec<String>,
    pub is_regex: bool,
    regex: Option<Regex>,
    /// `rxPrefix`: the ASCII literal every match must start with. Used exactly like Go's
    /// prefilter, so a rule that cannot match is rejected without running the regex.
    rx_prefix: String,
    wildcard: Option<WildcardMatcher>,
    pub include_qtypes: HashMap<u16, ()>,
    pub exclude_qtypes: HashMap<u16, ()>,
}

impl SpecialRule {
    /// `parseSpecialRule`. `None` means "drop the rule", the same outcome as Go returning nil
    /// (a regex that does not compile is logged there and dropped here).
    pub fn parse(cfg: &json::SpecialRule, is_allow: bool) -> Option<SpecialRule> {
        let is_regex = cfg.is_regex.unwrap_or(false);
        let mut rule = SpecialRule {
            pattern: go_trim_space(cfg.pattern.as_deref().unwrap_or("")).to_string(),
            source: cfg.source.clone().unwrap_or_default(),
            important: cfg.important.unwrap_or(false),
            is_allow,
            app_scope: HashMap::new(),
            app_inverted: cfg.app_inverted.unwrap_or(false),
            denyallow: Vec::new(),
            is_regex,
            regex: None,
            rx_prefix: String::new(),
            wildcard: None,
            include_qtypes: HashMap::new(),
            exclude_qtypes: HashMap::new(),
        };

        if is_regex {
            // Go keeps the raw pattern (only trimmed) and adds the `(?i)` prefix if missing.
            rule.regex = Some(regex_go::compile_rule_regex(&rule.pattern).ok()?);
            let anchored = if crate::text::has_fold_prefix(&rule.pattern) {
                rule.pattern.clone()
            } else {
                format!("(?i){0}", rule.pattern)
            };
            rule.rx_prefix = regex_go::anchored_prefix(&anchored);
        } else {
            rule.pattern = go_lower(&rule.pattern).into_owned();
            if cfg.is_wildcard.unwrap_or(false) || rule.pattern.contains('*') {
                rule.wildcard = WildcardMatcher::new(&rule.pattern);
            }
        }

        if let Some(scope) = cfg.app_scope.as_deref() {
            if !scope.is_empty() {
                for package in scope.split('|') {
                    let package = go_lower(go_trim_space(package)).into_owned();
                    if !package.is_empty() {
                        rule.app_scope.insert(package, ());
                    }
                }
            }
        }

        if let Some(denyallow) = cfg.denyallow.as_deref() {
            if !denyallow.is_empty() {
                for exception in denyallow.split('|') {
                    let exception = go_lower_trim_dot(exception);
                    if !exception.is_empty() {
                        rule.denyallow.push(exception);
                    }
                }
            }
        }

        if let Some(dns_type) = cfg.dns_type.as_deref() {
            if !dns_type.is_empty() {
                let mut raw = go_trim_space(dns_type).to_string();
                let is_negative = raw.starts_with('~');
                if is_negative {
                    raw = raw.strip_prefix('~').unwrap_or(&raw).to_string();
                }
                let mut types: HashMap<u16, ()> = HashMap::new();
                for token in raw.split('|') {
                    let token = go_trim_space(token);
                    let token = token.to_uppercase();
                    let token = token.strip_prefix('~').unwrap_or(&token);
                    if token.is_empty() {
                        continue;
                    }
                    if let Some(value) = crate::dns_type::string_to_type(token) {
                        types.insert(value, ());
                    }
                }
                if !types.is_empty() {
                    if is_negative {
                        rule.exclude_qtypes = types;
                    } else {
                        rule.include_qtypes = types;
                    }
                }
            }
        }

        Some(rule)
    }

    /// `specialRule.matches(domain, appName, qtype)` in Go's check order.
    pub fn matches(&self, domain: &str, app_name: &str, qtype: u16) -> bool {
        // 1. DNS query type.
        if !self.exclude_qtypes.is_empty() || !self.include_qtypes.is_empty() {
            if qtype == 0 {
                return false;
            }
            if self.exclude_qtypes.contains_key(&qtype) {
                return false;
            }
            if !self.include_qtypes.is_empty() && !self.include_qtypes.contains_key(&qtype) {
                return false;
            }
        }

        // 2. App scope.
        if !self.app_scope.is_empty() {
            if self.app_inverted {
                if !app_name.is_empty() && self.app_scope.contains_key(app_name) {
                    return false;
                }
            } else {
                if app_name.is_empty() || !self.app_scope.contains_key(app_name) {
                    return false;
                }
            }
        }

        // 3. denyallow exceptions exempt the whole subtree.
        for exception in &self.denyallow {
            if crate::text::domain_or_suffix(domain, exception) {
                return false;
            }
        }

        // 4. Pattern: regex, glob, or plain domain-or-suffix.
        if self.is_regex {
            match self.regex.as_ref() {
                Some(regex) => {
                    regex_go::may_match_prefix(domain, &self.rx_prefix) && regex.is_match(domain)
                }
                None => false,
            }
        } else if let Some(wildcard) = self.wildcard.as_ref() {
            wildcard.matches(domain)
        } else {
            crate::text::domain_or_suffix(domain, &self.pattern)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(config: serde_json::Value, is_allow: bool) -> SpecialRule {
        let cfg: json::SpecialRule = serde_json::from_value(config).expect("config");
        SpecialRule::parse(&cfg, is_allow).expect("rule")
    }

    #[test]
    fn plain_suffix_rule_lowercases_its_pattern() {
        let rule = rule(
            serde_json::json!({"pattern": " Example.COM ", "source": "s"}),
            false,
        );
        assert_eq!(rule.pattern, "example.com");
        assert!(rule.matches("example.com", "", 1));
        assert!(rule.matches("ads.example.com", "", 1));
        assert!(!rule.matches("notexample.com", "", 1));
    }

    #[test]
    fn denyallow_exempts_the_exception_subtree() {
        let rule = rule(
            serde_json::json!({"pattern": "example.com", "denyallow": "good.example.com|safe.example.com"}),
            false,
        );
        assert!(rule.matches("example.com", "", 1));
        assert!(!rule.matches("good.example.com", "", 1));
        assert!(!rule.matches("sub.good.example.com", "", 1));
        assert!(!rule.matches("safe.example.com", "", 1));
    }

    #[test]
    fn app_scope_includes_or_excludes() {
        let scoped = rule(
            serde_json::json!({"pattern": "a.com", "appScope": "com.a|com.b"}),
            false,
        );
        assert!(scoped.matches("a.com", "com.a", 1));
        assert!(!scoped.matches("a.com", "com.c", 1));
        assert!(!scoped.matches("a.com", "", 1));

        let inverted = rule(
            serde_json::json!({"pattern": "a.com", "appScope": "com.a", "appInverted": true}),
            false,
        );
        assert!(!inverted.matches("a.com", "com.a", 1));
        assert!(inverted.matches("a.com", "com.c", 1));
        assert!(inverted.matches("a.com", "", 1));
    }

    #[test]
    fn dns_type_includes_and_excludes() {
        let only_aaaa = rule(
            serde_json::json!({"pattern": "a.com", "dnsType": "AAAA"}),
            false,
        );
        assert!(!only_aaaa.matches("a.com", "", 1));
        assert!(only_aaaa.matches("a.com", "", 28));
        // qtype 0 (the MITM path) never matches a dnsType-constrained rule.
        assert!(!only_aaaa.matches("a.com", "", 0));

        let not_aaaa = rule(
            serde_json::json!({"pattern": "a.com", "dnsType": "~AAAA"}),
            false,
        );
        assert!(not_aaaa.matches("a.com", "", 1));
        assert!(!not_aaaa.matches("a.com", "", 28));
        assert!(!not_aaaa.matches("a.com", "", 0));
    }

    #[test]
    fn regex_rules_keep_the_raw_pattern_as_reason() {
        let rule = rule(
            serde_json::json!({"pattern": "^ad[s0-9]*\\.test\\.com$", "isRegex": true}),
            false,
        );
        assert_eq!(rule.pattern, "^ad[s0-9]*\\.test\\.com$");
        assert!(rule.matches("ad123.test.com", "", 1));
        assert!(!rule.matches("not-ads.test.com", "", 1));
    }

    #[test]
    fn regex_prefilter_rejects_without_changing_answers() {
        let rule = rule(
            serde_json::json!({"pattern": "^banner7\\..*\\.cn$", "isRegex": true}),
            false,
        );
        assert_eq!(rule.rx_prefix, "banner7.");
        assert!(rule.matches("banner7.x.cn", "", 1));
        assert!(!rule.matches("other.io", "", 1));
        // Non-ASCII domains are never rejected by the prefilter, only by the regex itself.
        assert!(!rule.matches("\u{4e2d}\u{56fd}.example", "", 1));
    }

    #[test]
    fn wildcard_special_rules_use_the_glob_matcher() {
        let rule = rule(serde_json::json!({"pattern": "ads*.example.org"}), false);
        assert!(rule.wildcard.is_some());
        assert!(rule.matches("ads1.example.org", "", 1));
        assert!(!rule.matches("ad.example.org", "", 1));
    }
}
