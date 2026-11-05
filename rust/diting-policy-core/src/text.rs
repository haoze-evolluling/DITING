//! Go-compatible string helpers.
//!
//! The Go policy engine lowercases and trims rule patterns with `strings.ToLower` /
//! `strings.TrimSpace` (Unicode simple case mapping, one rune in - one rune out). Rust's
//! `str::to_lowercase` applies the full case mapping instead, which differs for exactly one
//! codepoint (`U+0130` LATIN CAPITAL LETTER I WITH DOT ABOVE becomes `i` + combining dot, where Go
//! produces a plain `i`), so the fold is done per `char` with that override pinned.
//!
//! Domains on the hot path are *not* lowercased here: the Go caller already normalizes them before
//! the FFI call, so the boundary contract is "domain is lowercase, trimmed, no trailing dot".

use std::borrow::Cow;

/// `unicode.ToLower` for a single rune, spelled the way Go spells it.
fn go_lower_char(c: char) -> char {
    match c {
        // Go folds U+0130 to a plain ASCII `i`; Rust's full mapping adds U+0307.
        '\u{0130}' => 'i',
        _ => c.to_lowercase().next().unwrap_or(c),
    }
}

/// `strings.ToLower` (Unicode simple case mapping, context-free).
pub fn go_lower(s: &str) -> Cow<'_, str> {
    if s.is_ascii() {
        if s.bytes().any(|byte| byte.is_ascii_uppercase()) {
            return Cow::Owned(s.to_ascii_lowercase());
        }
        return Cow::Borrowed(s);
    }
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        out.push(go_lower_char(c));
    }
    Cow::Owned(out)
}

/// `strings.TrimSpace` (`unicode.IsSpace`, which is the Unicode `White_Space` property).
pub fn go_trim_space(s: &str) -> &str {
    s.trim_matches(char::is_whitespace)
}

/// `strings.ToLower(strings.TrimSpace(s))`, the shape used for every rule pattern.
pub fn go_lower_trim(s: &str) -> String {
    go_lower(go_trim_space(s)).into_owned()
}

/// `strings.TrimSuffix(strings.ToLower(strings.TrimSpace(s)), ".")`, the shape used for
/// `denyallow` exceptions and for the subscription trie keys.
pub fn go_lower_trim_dot(s: &str) -> String {
    let lowered = go_lower_trim(s);
    match lowered.strip_suffix('.') {
        Some(trimmed) => trimmed.to_string(),
        None => lowered,
    }
}

/// `strings.HasPrefix(s, "(?i)")`.
pub fn has_fold_prefix(s: &str) -> bool {
    s.starts_with("(?i)")
}

/// `strings.HasPrefix(domain, pattern)` and `domain == pattern`, i.e. `HasSuffix(domain, "."+pattern)`.
pub fn domain_or_suffix(domain: &str, pattern: &str) -> bool {
    domain == pattern
        || (domain.len() > pattern.len()
            && domain.ends_with(pattern)
            && domain.as_bytes()[domain.len() - pattern.len() - 1] == b'.')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lower_matches_go_simple_folding() {
        assert_eq!(go_lower("AbC"), "abc");
        // Go maps the dotted capital I to a plain `i`, Rust's full mapping would add U+0307.
        assert_eq!(go_lower("\u{0130}STANBUL"), "istanbul");
        // Context-free: no final sigma, unlike `str::to_lowercase`.
        assert_eq!(go_lower("ΑΣ"), "ασ");
        assert_eq!(go_lower("Straße"), "straße");
    }

    #[test]
    fn trim_and_dot_helpers() {
        assert_eq!(go_lower_trim("  Example.COM \t"), "example.com");
        assert_eq!(go_lower_trim_dot(" Example.COM. "), "example.com");
        assert_eq!(go_lower_trim_dot("example.com.."), "example.com.");
    }

    #[test]
    fn suffix_matching_needs_a_label_boundary() {
        assert!(domain_or_suffix("example.com", "example.com"));
        assert!(domain_or_suffix("ads.example.com", "example.com"));
        assert!(!domain_or_suffix("notexample.com", "example.com"));
        assert!(!domain_or_suffix("example.co", "example.com"));
    }
}
