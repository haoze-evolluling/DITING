use std::collections::HashSet;

use crate::models::ParsedRule;

fn is_unset(value: &Option<String>) -> bool {
    value.as_deref().is_none_or(str::is_empty)
}

/// 不带任何修饰或通配形式的域名规则按后缀匹配：`qq.com` 同时覆盖
/// `wechat.qq.com`。只要规则带有会改变匹配语义的字段，就不视为可继承。
pub fn is_plain_domain_rule(rule: &ParsedRule) -> bool {
    !rule.is_wildcard
        && !rule.is_regex
        && !rule.app_inverted
        && is_unset(&rule.app_scope)
        && is_unset(&rule.denyallow)
        && is_unset(&rule.dns_type)
}

/// 仅检查严格上级域名（至少多一级标签），规则自身不算冗余。
pub fn has_strict_ancestor(pattern: &str, contains: impl Fn(&str) -> bool) -> bool {
    let mut rest = pattern;
    while let Some(dot) = rest.find('.') {
        rest = &rest[dot + 1..];
        if rest.is_empty() {
            return false;
        }
        if contains(rest) {
            return true;
        }
    }
    false
}

/// 普通规则与 important 规则在不同优先级层匹配，所以父域名只覆盖同层的子域名。
#[derive(Default)]
pub struct PlainAncestors {
    normal: HashSet<String>,
    important: HashSet<String>,
}

impl PlainAncestors {
    pub fn insert(&mut self, rule: &ParsedRule) {
        if is_plain_domain_rule(rule) {
            self.insert_pattern(rule.important, &rule.pattern);
        }
    }

    pub fn insert_pattern(&mut self, important: bool, pattern: &str) {
        if pattern.is_empty() {
            return;
        }
        let set = if important {
            &mut self.important
        } else {
            &mut self.normal
        };
        if !set.contains(pattern) {
            set.insert(pattern.to_string());
        }
    }

    pub fn remove_pattern(&mut self, important: bool, pattern: &str) {
        if important {
            self.important.remove(pattern);
        } else {
            self.normal.remove(pattern);
        }
    }

    pub fn covers(&self, rule: &ParsedRule) -> bool {
        is_plain_domain_rule(rule) && self.covers_pattern(rule.important, &rule.pattern)
    }

    pub fn covers_pattern(&self, important: bool, pattern: &str) -> bool {
        let set = if important {
            &self.important
        } else {
            &self.normal
        };
        !set.is_empty() && has_strict_ancestor(pattern, |candidate| set.contains(candidate))
    }
}

/// 移除已被同一 importance 层级的普通父域名规则覆盖的屏蔽规则。
/// 返回保留的规则与被判为冗余的规则数。
pub fn drop_covered_block_rules(rules: Vec<ParsedRule>) -> (Vec<ParsedRule>, u32) {
    let mut ancestors = PlainAncestors::default();
    for rule in &rules {
        ancestors.insert(rule);
    }
    let mut removed = 0u32;
    let kept = rules
        .into_iter()
        .filter(|rule| {
            if ancestors.covers(rule) {
                removed += 1;
                false
            } else {
                true
            }
        })
        .collect();
    (kept, removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::document::parse_document;

    fn patterns(rules: &[ParsedRule]) -> Vec<&str> {
        rules.iter().map(|rule| rule.pattern.as_str()).collect()
    }

    #[test]
    fn a_plain_parent_makes_its_subdomains_redundant() {
        let parsed = parse_document("||qq.com^\n||wechat.qq.com^\n||mail.wechat.qq.com^\n");
        assert_eq!(patterns(&parsed.block_rules), ["qq.com"]);
        assert_eq!(parsed.duplicate_count, 2);
    }

    #[test]
    fn a_parent_declared_later_still_covers_earlier_children() {
        let parsed = parse_document("||wechat.qq.com^\n||qq.com^\n");
        assert_eq!(patterns(&parsed.block_rules), ["qq.com"]);
        assert_eq!(parsed.duplicate_count, 1);
    }

    #[test]
    fn a_badfiltered_parent_cannot_cover_its_subdomains() {
        let parsed = parse_document("||qq.com^\n||qq.com^$badfilter\n||wechat.qq.com^\n");
        assert_eq!(patterns(&parsed.block_rules), ["wechat.qq.com"]);
        assert_eq!(parsed.badfiltered_count, 1);
        assert_eq!(parsed.duplicate_count, 0);
    }

    #[test]
    fn different_importance_is_not_redundant() {
        let parsed = parse_document("||qq.com^\n||wechat.qq.com^$important\n");
        assert_eq!(patterns(&parsed.block_rules), ["qq.com", "wechat.qq.com"]);
        assert_eq!(parsed.duplicate_count, 0);
    }

    #[test]
    fn rules_with_different_matching_semantics_are_kept() {
        let parsed = parse_document(
            "||qq.com^\n\
             ||wechat.qq.com^$app=com.tencent.mm\n\
             ||*.qq.com^\n\
             /^mail\\.qq\\.com$/\n\
             ||qq.com^$denyallow=safe.qq.com\n\
             ||qq.com^$dnstype=A\n",
        );
        assert_eq!(
            patterns(&parsed.block_rules),
            [
                "qq.com",
                "wechat.qq.com",
                "*.qq.com",
                "^mail\\.qq\\.com$",
                "qq.com",
                "qq.com",
            ]
        );
        assert_eq!(parsed.duplicate_count, 0);
    }

    #[test]
    fn allow_rules_are_not_collapsed_by_the_parent() {
        let parsed = parse_document("@@||qq.com^\n@@||wechat.qq.com^\n");
        assert_eq!(patterns(&parsed.allow_rules), ["qq.com", "wechat.qq.com"]);
        assert_eq!(parsed.duplicate_count, 0);
    }

    #[test]
    fn a_not_suffix_alike_domain_is_not_covered() {
        let parsed = parse_document("||qq.com^\n||notqq.com^\n||qq.com.evil.net^\n");
        assert_eq!(
            patterns(&parsed.block_rules),
            ["qq.com", "notqq.com", "qq.com.evil.net"]
        );
        assert_eq!(parsed.duplicate_count, 0);
    }

    #[test]
    fn hosts_and_dnsmasq_lines_follow_the_same_hierarchy() {
        let parsed = parse_document("0.0.0.0 qq.com wechat.qq.com\naddress=/qq.com/mail.qq.com/\n");
        assert_eq!(patterns(&parsed.block_rules), ["qq.com"]);
        assert_eq!(parsed.duplicate_count, 3);
    }
}
