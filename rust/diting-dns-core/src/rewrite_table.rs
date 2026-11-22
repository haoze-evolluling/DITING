use std::collections::HashMap;

use diting_config_core::rewrite::{classify, normalize_domain, Entry};

#[derive(Debug, Default)]
pub struct RewriteTable {
    entries: HashMap<String, Entry>,
}

impl RewriteTable {
    pub fn build(entries: &[(String, Vec<String>)]) -> Self {
        let mut table = HashMap::with_capacity(entries.len());
        for (domain, targets) in entries {
            let key = normalize_domain(domain);
            if key.is_empty() {
                continue;
            }
            if let Some(entry) = classify(targets) {
                table.insert(key.into_owned(), entry);
            }
        }
        Self { entries: table }
    }

    pub fn lookup(&self, domain: &str) -> Option<&Entry> {
        let normalized = normalize_domain(domain);
        let mut candidate = normalized.as_ref();
        while !candidate.is_empty() {
            if let Some(entry) = self.entries.get(candidate) {
                return Some(entry);
            }
            match candidate.find('.') {
                Some(dot) => candidate = &candidate[dot + 1..],
                None => break,
            }
        }
        None
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
mod tests;
