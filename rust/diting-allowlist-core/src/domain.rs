use std::collections::HashSet;

use diting_go_compat::text::{go_lower, go_trim_space};

pub fn normalize_entry(raw: &str) -> Option<String> {
    let trimmed = go_trim_space(raw);
    let lowered = go_lower(trimmed);
    let stripped = lowered.strip_suffix('.').unwrap_or(&lowered);
    if stripped.is_empty() {
        return None;
    }
    Some(stripped.to_string())
}

pub fn normalize_query_name(name: &str) -> String {
    let lowered = go_lower(name);
    lowered.strip_suffix('.').unwrap_or(&lowered).to_string()
}

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
