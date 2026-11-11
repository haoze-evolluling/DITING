//! The engine's per-domain rewrite table: the decoded targets, the normalized keys and the
//! suffix walk `SetRewriteRules` / `rewriteLookup` used to run in Go.
//!
//! Classification itself is `diting-config-core`'s (`parseRewriteEntry`): the same function the
//! settings payload goes through, so a value cannot be classified one way when the table is built
//! and another way when it is read. What lives here is only the container: one entry per
//! normalized domain and the "strip one leading label and retry" walk.

use std::collections::HashMap;

use diting_config_core::rewrite::{classify, normalize_domain, Entry};

/// One published rewrite rule set. Immutable once built.
#[derive(Debug, Default)]
pub struct RewriteTable {
    entries: HashMap<String, Entry>,
}

impl RewriteTable {
    /// Builds the table from the decoded payload: one `(raw domain, raw targets)` pair per entry.
    ///
    /// The domain key is normalized here (trim, lowercase, one trailing dot) and blank keys are
    /// dropped; a value whose targets all vanish is dropped too, exactly like the old loop.
    pub fn build(entries: &[(String, Vec<String>)]) -> Self {
        let mut table = HashMap::with_capacity(entries.len());
        for (domain, targets) in entries {
            let key = normalize_domain(domain);
            if key.is_empty() {
                continue;
            }
            if let Some(entry) = classify(targets) {
                table.insert(key, entry);
            }
        }
        Self { entries: table }
    }

    /// `rewriteLookup`: the entry for the first matching suffix, else `None`.
    ///
    /// The walk is `strings.IndexByte(candidate, '.')`-compatible: it drops exactly one leading
    /// label per step, so `www.github.com` checks `www.github.com`, `github.com`, `com`.
    pub fn lookup(&self, domain: &str) -> Option<&Entry> {
        let mut candidate = normalize_domain(domain);
        while !candidate.is_empty() {
            if let Some(entry) = self.entries.get(&candidate) {
                return Some(entry);
            }
            match candidate.find('.') {
                Some(dot) => candidate = candidate[dot + 1..].to_string(),
                None => break,
            }
        }
        None
    }

    /// Number of stored entries (the old test read `len(engine.rewriteRules)`).
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// True when nothing was stored.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
mod tests;
