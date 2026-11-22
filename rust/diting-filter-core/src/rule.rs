use diting_go_compat::text::domain_or_suffix;
use regex::Regex;

pub const FLAG_ALLOW: u8 = 1 << 0;
pub const FLAG_IMPORTANT: u8 = 1 << 1;
pub const FLAG_REGEX: u8 = 1 << 2;
pub const FLAG_WILDCARD: u8 = 1 << 3;
pub const FLAG_EXACT: u8 = 1 << 4;
pub const FLAG_REWRITE: u8 = 1 << 5;

pub const KNOWN_FLAGS: u8 =
    FLAG_ALLOW | FLAG_IMPORTANT | FLAG_REGEX | FLAG_WILDCARD | FLAG_EXACT | FLAG_REWRITE;

pub const TYPE_ANY: u16 = 255;

pub const RCODE_SUCCESS: u8 = 0;
pub const TYPE_CNAME: u16 = 5;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RewriteAction {
    pub bare: bool,
    pub rcode: u8,
    pub rrtype: u16,
    pub key: String,
}

#[derive(Debug, Clone)]
pub struct Rule {
    pub pattern: String,
    pub regex: Option<Regex>,
    pub flags: u8,
    pub dns_type: u16,
    pub deny_allow: Vec<String>,
    pub to: Vec<String>,
    pub rewrite: Option<RewriteAction>,
}

impl Rule {
    pub fn new(pattern: impl Into<String>) -> Self {
        Self {
            pattern: pattern.into(),
            regex: None,
            flags: 0,
            dns_type: 0,
            deny_allow: Vec::new(),
            to: Vec::new(),
            rewrite: None,
        }
    }

    pub fn with_flags(mut self, flags: u8) -> Self {
        self.flags = flags;
        self
    }

    pub fn with_regex(mut self, regex: Regex) -> Self {
        self.regex = Some(regex);
        self
    }

    pub fn with_dns_type(mut self, dns_type: u16) -> Self {
        self.dns_type = dns_type;
        self
    }

    fn has(&self, flag: u8) -> bool {
        self.flags & flag != 0
    }

    pub fn is_allow(&self) -> bool {
        self.has(FLAG_ALLOW)
    }

    pub fn is_important(&self) -> bool {
        self.has(FLAG_IMPORTANT)
    }

    pub fn is_regex(&self) -> bool {
        self.has(FLAG_REGEX)
    }

    pub fn is_wildcard(&self) -> bool {
        self.has(FLAG_WILDCARD)
    }

    pub fn is_exact(&self) -> bool {
        self.has(FLAG_EXACT)
    }

    pub fn has_rewrite(&self) -> bool {
        self.has(FLAG_REWRITE)
    }

    pub fn is_pattern(&self) -> bool {
        self.is_regex() || self.is_wildcard()
    }

    pub fn matches_pattern(&self, domain: &str) -> bool {
        match &self.regex {
            Some(regex) => regex.is_match(domain),
            None => false,
        }
    }

    pub fn dns_type_matches(&self, qtype: u16) -> bool {
        self.dns_type == 0 || qtype == 0 || qtype == TYPE_ANY || self.dns_type == qtype
    }

    pub fn excludes(&self, domain: &str) -> bool {
        self.deny_allow
            .iter()
            .chain(self.to.iter())
            .any(|suffix| !suffix.is_empty() && domain_or_suffix(domain, suffix))
    }

    pub fn applicable(&self, domain: &str, qtype: u16) -> bool {
        self.dns_type_matches(qtype) && !self.excludes(domain)
    }

    pub fn covers(&self, domain: &str) -> bool {
        if self.is_pattern() {
            return self.matches_pattern(domain);
        }
        if self.pattern == domain {
            return true;
        }
        if self.is_exact() {
            return false;
        }
        domain_or_suffix(domain, &self.pattern)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_go_compat::regex::compile_rule_regex;

    #[test]
    fn dns_type_restrictions_ignore_any() {
        let rule = Rule::new("a.test").with_dns_type(1);
        assert!(rule.dns_type_matches(1));
        assert!(!rule.dns_type_matches(28));
        assert!(rule.dns_type_matches(TYPE_ANY));
        assert!(rule.dns_type_matches(0));
        assert!(Rule::new("a.test").dns_type_matches(28));
    }

    #[test]
    fn exclusions_need_a_label_boundary() {
        let mut rule = Rule::new("ads.com");
        rule.deny_allow = vec!["trusted.com".into()];
        rule.to = vec!["partner.net".into()];
        for domain in [
            "trusted.com",
            "a.trusted.com",
            "partner.net",
            "a.partner.net",
        ] {
            assert!(rule.excludes(domain), "{domain}");
        }
        for domain in ["untrusted.com", "nottrusted.com", "other.example.com"] {
            assert!(!rule.excludes(domain), "{domain}");
        }
        assert!(!rule.applicable("a.trusted.com", 1));
        assert!(rule.applicable("ads.com", 1));
    }

    #[test]
    fn cancellation_covers_subdomains_but_exact_rules_do_not() {
        let inherit = Rule::new("parent.test");
        assert!(inherit.covers("parent.test"));
        assert!(inherit.covers("deep.sub.parent.test"));
        assert!(!inherit.covers("notparent.test"));

        let exact = Rule::new("exact.test").with_flags(FLAG_EXACT);
        assert!(exact.covers("exact.test"));
        assert!(!exact.covers("sub.exact.test"));

        let pattern = Rule::new("*.wild.test")
            .with_flags(FLAG_WILDCARD)
            .with_regex(compile_rule_regex("(?i)^(?:.*\\.)?.*\\.wild\\.test$").expect("regex"));
        assert!(pattern.covers("anything.wild.test"));
        assert!(!pattern.covers("wild.test"));
    }

    #[test]
    fn a_rule_without_a_compiled_pattern_never_matches_by_pattern() {
        let rule = Rule::new("ads*").with_flags(FLAG_WILDCARD);
        assert!(!rule.matches_pattern("ads.example.com"));
    }
}
