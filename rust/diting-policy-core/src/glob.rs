//! Port of `newWildcardMatcher` (`android/engine/policy_matcher.go`).
//!
//! A wildcard rule is compiled to `(?i)^<glob with * -> .*>$`, exactly like Go does with
//! `regexp.QuoteMeta` + `regexp.Compile`. Both engines do Unicode simple case folding for `(?i)`,
//! so porting the compilation instead of hand-rolling a glob matcher keeps the folding orbits
//! (`s`/`ſ`, `k`/KELVIN SIGN) identical. `.*` is rune-wise in both.
//!
//! `*.example.com` additionally matches `example.com` itself (and its parent labels): the
//! `base_domain` field carries that shortcut.
//!
//! Compilation is lazy. A subscription rule set can carry thousands of globs and most of them never
//! match anything, while the Unicode `(?i)` compiler costs ~100 us per pattern: paid at snapshot
//! build time that made rule reloads several times slower than the Go engine, paid on first use it
//! is a one-off spike inside a single query. The answers are identical either way.

use std::sync::OnceLock;

use regex::Regex;

use crate::text::go_lower;

/// `wildcardMatcher`.
pub struct WildcardMatcher {
    /// The pattern as the caller stored it (already lowercased by the snapshot builder).
    pub pattern: String,
    /// `*.base` shortcut domain, empty when the pattern is not of that shape.
    pub base_domain: String,
    /// Pattern is exactly `*`.
    pub is_all: bool,
    /// Compiled on first use; `None` inside mirrors Go returning nil on a failed compile.
    regex: OnceLock<Option<Regex>>,
}

impl WildcardMatcher {
    /// `newWildcardMatcher`: `None` mirrors Go returning nil on a failed compile.
    pub fn new(pattern: &str) -> Option<WildcardMatcher> {
        if pattern == "*" {
            return Some(WildcardMatcher {
                pattern: pattern.to_string(),
                base_domain: String::new(),
                is_all: true,
                regex: OnceLock::new(),
            });
        }
        let mut base_domain = String::new();
        if let Some(rest) = pattern.strip_prefix("*.") {
            if !rest.is_empty() {
                base_domain = go_lower(rest.trim_end_matches('.')).into_owned();
            }
        }
        Some(WildcardMatcher {
            pattern: pattern.to_string(),
            base_domain,
            is_all: false,
            regex: OnceLock::new(),
        })
    }

    /// The compiled pattern, built once per matcher.
    fn regex(&self) -> Option<&Regex> {
        self.regex
            .get_or_init(|| {
                let mut source = String::with_capacity(self.pattern.len() + 8);
                source.push_str("(?i)^");
                for c in self.pattern.chars() {
                    if c == '*' {
                        source.push_str(".*");
                    } else {
                        source.push_str(&regex::escape(&c.to_string()));
                    }
                }
                source.push('$');
                Regex::new(&source).ok()
            })
            .as_ref()
    }

    /// `matches`: the pattern itself, then every parent label of the domain, is tried.
    pub fn matches(&self, domain: &str) -> bool {
        if self.is_all {
            return true;
        }
        if !self.base_domain.is_empty() && domain == self.base_domain {
            return true;
        }
        let Some(regex) = self.regex() else {
            return false;
        };
        if regex.is_match(domain) {
            return true;
        }
        // Parent labels, left to right; a trailing dot yields no empty suffix (same as Go).
        let mut start = 0usize;
        while let Some(relative) = domain[start..].find('.') {
            let dot = start + relative;
            if dot + 1 >= domain.len() {
                break;
            }
            start = dot + 1;
            let d = &domain[start..];
            if !self.base_domain.is_empty() && d == self.base_domain {
                return true;
            }
            if regex.is_match(d) {
                return true;
            }
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wildcard_short_circuits() {
        let all = WildcardMatcher::new("*").unwrap();
        assert!(all.matches("anything.example"));
        assert!(all.is_all);
    }

    #[test]
    fn star_dot_base_matches_base_and_children() {
        let m = WildcardMatcher::new("*.example.com").unwrap();
        assert_eq!(m.base_domain, "example.com");
        assert!(m.matches("example.com"));
        assert!(m.matches("a.example.com"));
        assert!(m.matches("a.b.example.com"));
        assert!(!m.matches("notexample.com"));
        assert!(!m.matches("example.com.cn"));
    }

    #[test]
    fn infix_globs_and_case_folding() {
        let m = WildcardMatcher::new("ads*.example.org").unwrap();
        assert!(m.matches("ads1.example.org"));
        assert!(m.matches("ads.example.org"));
        assert!(!m.matches("ad.example.org"));
        // `(?i)` folding is Unicode simple folding, same as Go's regexp.
        let folded = WildcardMatcher::new("s*.example.org").unwrap();
        assert!(folded.matches("\u{017F}1.example.org"));
    }

    #[test]
    fn dot_inside_star_stays_dot_separated() {
        let m = WildcardMatcher::new("a*b.c").unwrap();
        assert!(m.matches("axb.c"));
        assert!(m.matches("a.b.c"));
        // `*` is `.*`, so it may match nothing at all.
        assert!(m.matches("ab.c"));
        assert!(!m.matches("ab.cc"));
    }

    #[test]
    fn trailing_dot_pattern_still_matches_the_trimmed_parent() {
        // `*.foo.` keeps the raw glob but the base domain is `foo`.
        let m = WildcardMatcher::new("*.foo.").unwrap();
        assert_eq!(m.base_domain, "foo");
        assert!(m.matches("a.foo"));
        assert!(m.matches("foo"));
    }
}
