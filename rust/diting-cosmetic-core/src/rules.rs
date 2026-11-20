use std::collections::{HashMap, HashSet};

use crate::host::normalize_host;

pub const NO_RULES: &str = "/* DITING: no cosmetic rules loaded */";

pub const INVALID_RULES: &str = "/* DITING: invalid cosmetic rules */";

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct DomainRules {
    pub hide: Vec<String>,
    pub exception: Vec<String>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Rules {
    pub global_hide: Vec<String>,
    pub global_exception: Vec<String>,
    pub domains: HashMap<String, DomainRules>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuleSet {
    Empty,
    Invalid,
    Loaded(Rules),
}

impl RuleSet {
    pub fn is_empty(&self) -> bool {
        matches!(self, RuleSet::Empty)
    }

    pub fn render(&self, host: &str) -> String {
        match self {
            RuleSet::Empty => NO_RULES.to_string(),
            RuleSet::Invalid => INVALID_RULES.to_string(),
            RuleSet::Loaded(rules) => rules.render(host),
        }
    }
}

impl Rules {
    fn render(&self, host: &str) -> String {
        let mut hide: HashSet<&str> = self.global_hide.iter().map(String::as_str).collect();
        let mut exceptions: HashSet<&str> =
            self.global_exception.iter().map(String::as_str).collect();

        for domain in host_suffixes(host) {
            let Some(entry) = self.domains.get(&domain) else {
                continue;
            };
            hide.extend(entry.hide.iter().map(String::as_str));
            exceptions.extend(entry.exception.iter().map(String::as_str));
        }

        let mut hidden: Vec<&str> = hide
            .iter()
            .copied()
            .filter(|selector| !exceptions.contains(selector))
            .collect();
        hidden.sort_unstable();
        let mut excepted: Vec<&str> = exceptions.into_iter().collect();
        excepted.sort_unstable();

        let mut css = String::new();
        for selector in hidden {
            css.push_str(selector);
            css.push_str(" { display: none !important; }\n");
        }
        for selector in excepted {
            css.push_str(selector);
            css.push_str(" { display: revert !important; }\n");
        }
        css
    }
}

pub fn host_suffixes(host: &str) -> Vec<String> {
    let mut remaining = normalize_host(host);
    if remaining.is_empty() {
        return Vec::new();
    }
    let mut suffixes = vec![remaining.clone()];
    loop {
        match remaining.find('.') {
            None => return suffixes,
            Some(index) if index == remaining.len() - 1 => return suffixes,
            Some(index) => {
                remaining = remaining[index + 1..].to_string();
                suffixes.push(remaining.clone());
            }
        }
    }
}

#[cfg(test)]
mod tests;
