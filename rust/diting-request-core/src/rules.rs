//! The rule table: normalization and the kind/prefix whitelist.
//!
//! `SetRequestRules` used to normalize each rule in place and keep only the ones it could match with:
//! a `block` or `allow` kind and a pattern that starts with `http://` or `https://`. Everything else
//! was dropped without a log line, which is why the drop has to be silent here too.

use diting_go_compat::text::{go_lower, go_trim_space};

/// One normalized rule.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rule {
    /// `false` for `block`, `true` for `allow`.
    pub allow: bool,
    /// Lower-cased, trimmed, scheme-prefixed URL prefix.
    pub pattern: String,
}

/// Normalizes one incoming rule; `None` means the old code dropped it.
///
/// The kind is compared exactly (`BLOCK`, `block ` and `deny` are all dropped); only the pattern is
/// trimmed and lower-cased.
pub fn normalize(kind: &str, pattern: &str) -> Option<Rule> {
    let allow = match kind {
        "block" => false,
        "allow" => true,
        _ => return None,
    };
    let pattern = go_lower(go_trim_space(pattern)).into_owned();
    if !pattern.starts_with("http://") && !pattern.starts_with("https://") {
        return None;
    }
    Some(Rule { allow, pattern })
}

/// Normalizes a whole incoming list, keeping the order and dropping the invalid rules.
pub fn normalize_all(rules: &[(String, String)]) -> Vec<Rule> {
    rules
        .iter()
        .filter_map(|(kind, pattern)| normalize(kind, pattern))
        .collect()
}

#[cfg(test)]
mod tests;
