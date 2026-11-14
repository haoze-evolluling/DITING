//! Rule-version diff and bounded history.
//!
//! Both functions are pure and deterministic. [`diff`] compares two rule sets as ordered unique
//! lists; [`record`] maintains a newest-first history capped at [`DEFAULT_MAX_VERSIONS`]. A version
//! is identified by the rule-set hash the caller already computes (`ruleSetHash`), so a re-download
//! that did not change the set does not create a new version.

/// How many versions the history keeps by default.
pub const DEFAULT_MAX_VERSIONS: usize = 10;

/// Upper bound on versions a caller may ask to keep.
pub const MAX_VERSIONS_LIMIT: usize = 50;

/// Upper bound on the sample rules returned per side of a diff, so a huge update stays cheap to
/// render; `added_count` / `removed_count` always carry the full totals.
pub const SAMPLE_LIMIT: usize = 200;

/// One stored rule-set version.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VersionEntry {
    /// The rule-set hash (`ruleSetHash`), the version identity.
    pub hash: String,
    /// Number of rules in the snapshot.
    pub rule_count: i64,
    /// When the snapshot was recorded (epoch ms).
    pub created_at: i64,
}

/// The difference between two rule sets.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RuleDiff {
    /// Rules present in `new` but not `old`, in `new` order (sampled at [`SAMPLE_LIMIT`]).
    pub added: Vec<String>,
    /// Rules present in `old` but not `new`, in `old` order (sampled at [`SAMPLE_LIMIT`]).
    pub removed: Vec<String>,
    /// Full count of added rules.
    pub added_count: i64,
    /// Full count of removed rules.
    pub removed_count: i64,
    /// Rules present in both.
    pub unchanged_count: i64,
    /// `old.len() - new.len()` (positive when the new set shrank).
    pub delta: i64,
}

/// Ordered unique view of a rule list: drops blanks and later duplicates, keeps first occurrence.
fn unique(list: &[String]) -> Vec<&str> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for item in list {
        let trimmed = item.trim();
        if trimmed.is_empty() {
            continue;
        }
        if seen.insert(trimmed) {
            out.push(trimmed);
        }
    }
    out
}

/// `diff`: what changed between `old` and `new`.
pub fn diff(old: &[String], new: &[String]) -> RuleDiff {
    let old_unique = unique(old);
    let new_unique = unique(new);
    let old_set: std::collections::HashSet<&str> = old_unique.iter().copied().collect();
    let new_set: std::collections::HashSet<&str> = new_unique.iter().copied().collect();

    let mut added_all: Vec<&str> = Vec::new();
    for rule in &new_unique {
        if !old_set.contains(rule) {
            added_all.push(rule);
        }
    }
    let mut removed_all: Vec<&str> = Vec::new();
    for rule in &old_unique {
        if !new_set.contains(rule) {
            removed_all.push(rule);
        }
    }
    let unchanged_count = new_unique.len() - added_all.len();

    RuleDiff {
        added: added_all
            .iter()
            .take(SAMPLE_LIMIT)
            .map(|s| s.to_string())
            .collect(),
        removed: removed_all
            .iter()
            .take(SAMPLE_LIMIT)
            .map(|s| s.to_string())
            .collect(),
        added_count: added_all.len() as i64,
        removed_count: removed_all.len() as i64,
        unchanged_count: unchanged_count as i64,
        delta: new_unique.len() as i64 - old_unique.len() as i64,
    }
}

/// `record`: prepend a snapshot to a newest-first history.
///
/// A snapshot identical to the current head is not recorded again (unchanged re-download). The
/// history is capped at `max` (defaulting to [`DEFAULT_MAX_VERSIONS`], clamped to a sane range).
pub fn record(
    existing: &[VersionEntry],
    hash: &str,
    rule_count: i64,
    created_at: i64,
    max: Option<usize>,
) -> Vec<VersionEntry> {
    let limit = match max {
        Some(0) | None => DEFAULT_MAX_VERSIONS,
        Some(value) => value.min(MAX_VERSIONS_LIMIT),
    };
    if let Some(head) = existing.first() {
        if head.hash == hash {
            return existing.to_vec();
        }
    }
    let mut result = Vec::with_capacity(existing.len() + 1);
    result.push(VersionEntry {
        hash: hash.to_string(),
        rule_count,
        created_at,
    });
    for entry in existing {
        if entry.hash == hash {
            continue;
        }
        result.push(entry.clone());
        if result.len() >= limit {
            break;
        }
    }
    result.truncate(limit);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rules(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    fn entry(hash: &str, count: i64, at: i64) -> VersionEntry {
        VersionEntry {
            hash: hash.to_string(),
            rule_count: count,
            created_at: at,
        }
    }

    #[test]
    fn diff_reports_added_removed_and_unchanged() {
        let d = diff(&rules(&["a", "b", "c"]), &rules(&["b", "c", "d"]));
        assert_eq!(d.added, rules(&["d"]));
        assert_eq!(d.removed, rules(&["a"]));
        assert_eq!(d.added_count, 1);
        assert_eq!(d.removed_count, 1);
        assert_eq!(d.unchanged_count, 2);
        assert_eq!(d.delta, 0);
    }

    #[test]
    fn diff_dedupes_and_ignores_blanks() {
        let d = diff(&rules(&["a", "a", " "]), &rules(&["a", "b", "b"]));
        assert_eq!(d.added_count, 1);
        assert_eq!(d.removed_count, 0);
        assert_eq!(d.unchanged_count, 1);
    }

    #[test]
    fn diff_samples_but_counts_everything() {
        let old: Vec<String> = (0..300).map(|i| format!("old{i}")).collect();
        let new: Vec<String> = (0..400).map(|i| format!("new{i}")).collect();
        let d = diff(&old, &new);
        assert_eq!(d.added.len(), SAMPLE_LIMIT);
        assert_eq!(d.removed.len(), SAMPLE_LIMIT);
        assert_eq!(d.added_count, 400);
        assert_eq!(d.removed_count, 300);
        assert_eq!(d.delta, 100);
    }

    #[test]
    fn record_prepends_new_head() {
        let existing = vec![entry("h2", 20, 200)];
        let next = record(&existing, "h3", 30, 300, None);
        assert_eq!(next.first().unwrap().hash, "h3");
        assert_eq!(next.len(), 2);
    }

    #[test]
    fn record_skips_unchanged_head() {
        let existing = vec![entry("h2", 20, 200)];
        let next = record(&existing, "h2", 999, 999, None);
        assert_eq!(next, existing);
    }

    #[test]
    fn record_caps_history() {
        let mut history = Vec::new();
        for i in 0..20 {
            history = record(&history, &format!("h{i}"), i, i, Some(5));
        }
        assert_eq!(history.len(), 5);
        assert_eq!(history.first().unwrap().hash, "h19");
        assert_eq!(history.last().unwrap().hash, "h15");
    }

    #[test]
    fn record_drops_a_duplicate_deeper_in_history() {
        let existing = vec![entry("h1", 1, 1), entry("h2", 2, 2)];
        let next = record(&existing, "h1", 1, 3, None);
        assert_eq!(next.iter().filter(|e| e.hash == "h1").count(), 1);
        assert_eq!(next.first().unwrap().hash, "h1");
    }
}
