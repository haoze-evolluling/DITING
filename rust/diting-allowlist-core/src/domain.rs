//! Domain normalization and the suffix walk, ported from `domainMatches` and `SetAppAllowlist`.
//!
//! Two normalizations exist in the Go code and they are deliberately not the same:
//!
//! * config entries: `strings.TrimSuffix(strings.ToLower(strings.TrimSpace(raw)), ".")` — trim,
//!   lowercase, then drop exactly one trailing dot; an empty result is skipped;
//! * query names: `strings.TrimSuffix(strings.ToLower(name), ".")` — no trimming, exactly one
//!   trailing dot.
//!
//! `strings.ToLower` is the Unicode simple case mapping, so the shared `go_lower` is used instead
//! of `str::to_lowercase` (which expands `U+0130` into `i` + combining dot). The corpus pins the
//! difference.

use std::collections::HashSet;

use diting_go_compat::text::{go_lower, go_trim_space};

/// `SetAppAllowlist`'s per-domain normalization. Returns `None` for an entry that becomes empty.
pub fn normalize_entry(raw: &str) -> Option<String> {
    let trimmed = go_trim_space(raw);
    let lowered = go_lower(trimmed);
    let stripped = lowered.strip_suffix('.').unwrap_or(&lowered);
    if stripped.is_empty() {
        return None;
    }
    Some(stripped.to_string())
}

/// `rememberAppAllowlistResponse`'s question-name normalization (no trimming).
pub fn normalize_query_name(name: &str) -> String {
    let lowered = go_lower(name);
    lowered.strip_suffix('.').unwrap_or(&lowered).to_string()
}

/// `domainMatches`: walk the domain and every parent suffix (one label at a time) and report
/// whether one of them is in `allowed`. The walk stops at the first dot; an empty candidate ends
/// it, so the empty string is never tested even if a set contains it.
pub fn domain_matches(allowed: &HashSet<String>, domain: &str) -> bool {
    if allowed.is_empty() {
        return false;
    }
    let lowered = go_lower(domain);
    let mut candidate = lowered.strip_suffix('.').unwrap_or(&lowered);
    while !candidate.is_empty() {
        if allowed.contains(candidate) {
            return true;
        }
        match candidate.find('.') {
            Some(dot) => candidate = &candidate[dot + 1..],
            None => break,
        }
    }
    false
}

#[cfg(test)]
mod tests;
