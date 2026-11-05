//! Rule dedupe keys, a port of `adblock_rule_keys.dart`.
//!
//! A key must include every distinguishing dimension (`important`, `appScope`, `appInverted`, plus
//! the optional `denyallow` / `isRegex` / `dnsType`), or distinct rules would merge.

use crate::models::{ParsedRewriteRule, ParsedRule};

/// Rule dedupe keys. A key must include every distinguishing dimension (`important`, `appScope`,
/// `appInverted`), or distinct rules would merge.
// Mirrors the Dart `blockRuleKey`/`allowRuleKey` signatures field for field, so the two stay
// obviously comparable; folding the dimensions into a struct would hide that.
#[allow(clippy::too_many_arguments)]
pub fn rule_key(
    prefix: &str,
    pattern: &str,
    important: bool,
    app_scope: Option<&str>,
    app_inverted: bool,
    denyallow: Option<&str>,
    is_regex: bool,
    dns_type: Option<&str>,
) -> String {
    // `$appScope` on a null String interpolates as "null" in Dart; keep that text.
    let base = format!(
        "{prefix}:{pattern}:{important}:{}:{app_inverted}",
        app_scope.unwrap_or("null")
    );
    let has_extra = denyallow.is_some_and(|value| !value.is_empty())
        || is_regex
        || dns_type.is_some_and(|value| !value.is_empty());
    if !has_extra {
        return base;
    }
    format!(
        "{base}:{}:{is_regex}:{}",
        denyallow.unwrap_or(""),
        dns_type.unwrap_or("")
    )
}

pub fn rule_key_of(prefix: &str, rule: &ParsedRule) -> String {
    rule_key(
        prefix,
        &rule.pattern,
        rule.important,
        rule.app_scope.as_deref(),
        rule.app_inverted,
        rule.denyallow.as_deref(),
        rule.is_regex,
        rule.dns_type.as_deref(),
    )
}

pub fn block_key_of(rule: &ParsedRule) -> String {
    rule_key_of("block", rule)
}

pub fn allow_key_of(rule: &ParsedRule) -> String {
    rule_key_of("allow", rule)
}

pub fn rewrite_key_of(rule: &ParsedRewriteRule) -> String {
    format!(
        "rewrite:{}:{}:{}",
        rule.pattern, rule.target_type, rule.target_value
    )
}

pub fn url_key(prefix: &str, pattern: &str, app_scope: Option<&str>) -> String {
    format!("{prefix}:{pattern}:{}", app_scope.unwrap_or("null"))
}
