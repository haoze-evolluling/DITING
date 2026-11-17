//! `excludePatterns`: domains that bypass the cache entirely.
//!
//! The Go service compiles at most 256 patterns of at most 512 bytes and refuses to fail the whole
//! cache because one pattern is malformed. The same bounds apply here; Rust's `regex` crate is a
//! finite-automaton engine, so a hostile pattern cannot backtrack catastrophically.

use std::sync::atomic::{AtomicU64, Ordering};

use regex::{Regex, RegexSet};

pub const MAX_PATTERNS: usize = 256;
pub const MAX_PATTERN_LEN: usize = 512;

pub struct CacheExcluder {
    patterns: Vec<String>,
    set: Option<RegexSet>,
    hits: AtomicU64,
}

impl CacheExcluder {
    /// Compiles the patterns, dropping invalid/oversized ones and returning their diagnostics. The
    /// excluder is always usable, even when every pattern was rejected.
    pub fn new(patterns: &[String]) -> (Self, Vec<String>) {
        let mut problems = Vec::new();
        let mut accepted = Vec::new();
        for raw in patterns {
            let pattern = raw.trim();
            if pattern.is_empty() {
                continue;
            }
            if accepted.len() >= MAX_PATTERNS {
                problems.push(format!("exclude patterns over the limit {MAX_PATTERNS}; rest ignored"));
                break;
            }
            if pattern.len() > MAX_PATTERN_LEN {
                problems.push(format!(
                    "exclude pattern {} exceeds {MAX_PATTERN_LEN} bytes; ignored",
                    truncate(pattern)
                ));
                continue;
            }
            accepted.push(pattern.to_string());
        }
        // Validate one pattern at a time: `RegexSet::new` rejects the whole set when a single
        // member is malformed, while the Go service skipped only the bad pattern. An invalid
        // pattern is reported and removed; the remaining exclusions keep working.
        let valid: Vec<String> = accepted
            .iter()
            .filter(|pattern| match Regex::new(pattern) {
                Ok(_) => true,
                Err(error) => {
                    problems.push(format!(
                        "exclude pattern {} rejected: {error}",
                        truncate(pattern)
                    ));
                    false
                }
            })
            .cloned()
            .collect();
        let set = if valid.is_empty() {
            None
        } else {
            match RegexSet::new(&valid) {
                Ok(set) => Some(set),
                Err(error) => {
                    problems.push(format!("exclude patterns rejected: {error}"));
                    None
                }
            }
        };
        (
            Self {
                patterns: valid,
                set,
                hits: AtomicU64::new(0),
            },
            problems,
        )
    }

    pub fn is_excluded(&self, domain: &str) -> bool {
        let Some(set) = &self.set else {
            return false;
        };
        let normalized = normalize_domain(domain);
        if normalized.is_empty() {
            return false;
        }
        if set.is_match(&normalized) {
            self.hits.fetch_add(1, Ordering::Relaxed);
            true
        } else {
            false
        }
    }

    pub fn patterns(&self) -> &[String] {
        &self.patterns
    }

    pub fn hits(&self) -> u64 {
        self.hits.load(Ordering::Relaxed)
    }

    pub fn len(&self) -> usize {
        self.patterns.len()
    }

    pub fn is_empty(&self) -> bool {
        self.patterns.is_empty()
    }
}

pub fn normalize_domain(domain: &str) -> String {
    domain.trim().trim_end_matches('.').to_ascii_lowercase()
}

fn truncate(text: &str) -> String {
    const LIMIT: usize = 64;
    if text.len() <= LIMIT {
        return text.to_string();
    }
    format!("{}...", &text[..LIMIT])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_case_and_trailing_dot_insensitively() {
        let (excluder, problems) = CacheExcluder::new(&["(^|\\.)example\\.com$".to_string()]);
        assert!(problems.is_empty());
        assert!(excluder.is_excluded("WWW.Example.com."));
        assert!(!excluder.is_excluded("example.org"));
        assert_eq!(excluder.hits(), 1);
    }

    #[test]
    fn invalid_patterns_do_not_disable_the_rest() {
        let (excluder, problems) = CacheExcluder::new(&["[".to_string(), "ads".to_string()]);
        assert!(!problems.is_empty());
        assert!(excluder.is_excluded("ads.test"));
    }
}
