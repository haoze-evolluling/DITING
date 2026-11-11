//! Rule models. Field-for-field mirrors of `android/app/lib/data/rules/rule_models.dart`;
//! the Dart side rebuilds its own objects from the FFI payload, so field order matters there
//! (see `ffi.rs`) as much as the semantics do.

use std::collections::HashSet;

/// `RewriteTargetType` values as they are stored in the database.
pub const REWRITE_IPV4: &str = "IPv4";
pub const REWRITE_IPV6: &str = "IPv6";
pub const REWRITE_CNAME: &str = "CNAME";

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ParsedRule {
    pub pattern: String,
    pub raw_line: String,
    pub important: bool,
    pub app_scope: Option<String>,
    pub app_inverted: bool,
    pub is_wildcard: bool,
    pub denyallow: Option<String>,
    pub is_regex: bool,
    pub dns_type: Option<String>,
}

impl ParsedRule {
    pub fn new(pattern: String, raw_line: String) -> Self {
        Self {
            pattern,
            raw_line,
            ..Self::default()
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ParsedRewriteRule {
    pub pattern: String,
    pub target_type: String,
    pub target_value: String,
    pub raw_line: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ParsedUrlRule {
    pub pattern: String,
    pub raw_line: String,
    pub is_allow: bool,
    pub app_scope: Option<String>,
    pub important: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ParsedCosmeticRule {
    pub domain: String,
    pub selector: String,
    pub raw_line: String,
    pub is_exception: bool,
}

/// Result of parsing one line; one line may expand into several rules.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CategorizedLine {
    pub block_rules: Vec<ParsedRule>,
    pub allow_rules: Vec<ParsedRule>,
    pub rewrite_rules: Vec<ParsedRewriteRule>,
    pub url_block_rules: Vec<ParsedUrlRule>,
    pub url_allow_rules: Vec<ParsedUrlRule>,
    pub cosmetic_rules: Vec<ParsedCosmeticRule>,
    pub badfilter_keys: HashSet<String>,
    pub invalid_count: u32,
    pub unsupported_count: u32,
    pub ignored_count: u32,
}

impl CategorizedLine {
    pub fn invalid() -> Self {
        Self {
            invalid_count: 1,
            ..Self::default()
        }
    }

    pub fn invalid_n(count: u32) -> Self {
        Self {
            invalid_count: count,
            ..Self::default()
        }
    }

    pub fn unsupported() -> Self {
        Self {
            unsupported_count: 1,
            ..Self::default()
        }
    }

    pub fn ignored() -> Self {
        Self {
            ignored_count: 1,
            ..Self::default()
        }
    }

    pub fn is_empty(&self) -> bool {
        self.block_rules.is_empty()
            && self.allow_rules.is_empty()
            && self.rewrite_rules.is_empty()
            && self.url_block_rules.is_empty()
            && self.url_allow_rules.is_empty()
            && self.cosmetic_rules.is_empty()
    }
}

/// Whole-document parse result; the counters are the ones the import summary reports.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CategorizedRules {
    pub block_rules: Vec<ParsedRule>,
    pub allow_rules: Vec<ParsedRule>,
    pub rewrite_rules: Vec<ParsedRewriteRule>,
    pub url_block_rules: Vec<ParsedUrlRule>,
    pub url_allow_rules: Vec<ParsedUrlRule>,
    pub cosmetic_rules: Vec<ParsedCosmeticRule>,
    pub duplicate_count: u32,
    pub invalid_count: u32,
    pub unsupported_count: u32,
    pub ignored_count: u32,
    pub badfiltered_count: u32,
    pub total_lines: u32,
}

impl CategorizedRules {
    pub fn size(&self) -> usize {
        self.block_rules.len()
            + self.allow_rules.len()
            + self.rewrite_rules.len()
            + self.url_block_rules.len()
            + self.url_allow_rules.len()
            + self.cosmetic_rules.len()
    }

    pub fn is_empty(&self) -> bool {
        self.size() == 0
    }
}
