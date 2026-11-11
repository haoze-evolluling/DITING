//! Rule tables, buckets and inverted rules that `Snapshot` is made of
//! (`appRuleBucket`, `invertedRule` and the matching helpers in `policy_snapshot.go`).
//!
//! Split out of [`crate::snapshot`] to keep each file reviewable; nothing here knows about the
//! priority order, it only answers "does this table hold this domain".

use std::collections::HashMap;
use std::sync::Arc;

use crate::dtri_read::{open_shared, DtriReader};
use crate::glob::WildcardMatcher;
use crate::json;
use crate::special::SpecialRule;
use crate::text::{domain_or_suffix, go_lower_trim};
use crate::wildcard_index::WildcardIndex;

/// `appRuleBucket`.
#[derive(Default)]
pub(crate) struct AppRuleBucket {
    pub(crate) allow: HashMap<String, ()>,
    pub(crate) block: HashMap<String, String>,
    pub(crate) important: HashMap<String, String>,
    pub(crate) allow_wildcards: Option<WildcardIndex>,
    pub(crate) block_wildcards: Option<WildcardIndex>,
    pub(crate) important_wildcards: Option<WildcardIndex>,
}

/// `invertedRule`.
pub(crate) struct InvertedRule {
    pub(crate) pattern: String,
    pub(crate) excluded_apps: HashMap<String, ()>,
    pub(crate) wildcard: Option<WildcardMatcher>,
}

/// `matchDomainOrSuffix`: the value of the longest matching suffix in map order.
pub(crate) fn match_domain_or_suffix<'a>(
    domain: &str,
    table: &'a HashMap<String, String>,
) -> Option<&'a String> {
    if table.is_empty() {
        return None;
    }
    if let Some(value) = table.get(domain) {
        return Some(value);
    }
    let mut start = 0usize;
    while let Some(relative) = domain[start..].find('.') {
        let dot = start + relative;
        if dot + 1 >= domain.len() {
            break;
        }
        start = dot + 1;
        if let Some(value) = table.get(&domain[start..]) {
            return Some(value);
        }
    }
    None
}

/// `matchDomainOrSuffixSet`.
pub(crate) fn match_domain_or_suffix_set(domain: &str, table: &HashMap<String, ()>) -> bool {
    if table.is_empty() {
        return false;
    }
    if table.contains_key(domain) {
        return true;
    }
    let mut start = 0usize;
    while let Some(relative) = domain[start..].find('.') {
        let dot = start + relative;
        if dot + 1 >= domain.len() {
            break;
        }
        start = dot + 1;
        if table.contains_key(&domain[start..]) {
            return true;
        }
    }
    false
}

pub(crate) fn wildcard_list(patterns: &[String], out: &mut Vec<Arc<WildcardMatcher>>) {
    for pattern in patterns {
        if let Some(matcher) = WildcardMatcher::new(pattern) {
            out.push(Arc::new(matcher));
        }
    }
}

pub(crate) enum GlobSlot<'a> {
    Important(&'a mut Vec<Arc<WildcardMatcher>>),
    Allow(&'a mut Vec<Arc<WildcardMatcher>>),
    Block(&'a mut Vec<Arc<WildcardMatcher>>),
}

pub(crate) fn parse_inverted(config: &json::InvertedRule) -> Option<InvertedRule> {
    let pattern = go_lower_trim(config.pattern.as_deref().unwrap_or(""));
    if pattern.is_empty() {
        return None;
    }
    let mut excluded_apps = HashMap::new();
    for app in config.excluded_apps.as_deref().unwrap_or(&[]) {
        let app = go_lower_trim(app);
        if !app.is_empty() {
            excluded_apps.insert(app, ());
        }
    }
    let wildcard = if pattern.contains('*') {
        WildcardMatcher::new(&pattern)
    } else {
        None
    };
    Some(InvertedRule {
        pattern,
        excluded_apps,
        wildcard,
    })
}

pub(crate) fn parse_special(config: &json::SpecialRule, is_allow: bool) -> Option<SpecialRule> {
    SpecialRule::parse(config, is_allow)
}

pub(crate) fn skipped_inverted(rule: &InvertedRule, app_name: &str) -> bool {
    !app_name.is_empty() && rule.excluded_apps.contains_key(app_name)
}

pub(crate) fn inverted_matches(rule: &InvertedRule, domain: &str) -> bool {
    match rule.wildcard.as_ref() {
        Some(wildcard) => wildcard.matches(domain),
        None => domain_or_suffix(domain, &rule.pattern),
    }
}

pub(crate) fn open_trie(path: Option<&str>) -> Option<Arc<DtriReader>> {
    let path = path?;
    if path.is_empty() {
        return None;
    }
    open_shared(path).ok()
}
