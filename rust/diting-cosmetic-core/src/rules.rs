//! The cosmetic rule set, compiled once per push and rendered per stylesheet request.
//!
//! `SetCosmeticRules` used to keep the raw JSON and re-run `encoding/json` plus two maps on *every*
//! `/cosmetic.css` request (`buildCosmeticCss`). The split here is: Go keeps `encoding/json` (the
//! payload is Kotlin's, and a faithful JSON decoder is not this kernel's job), decodes it once, and
//! hands the kernel a flat rule set. The kernel owns the lookup and the rendering:
//!
//! * [`host_suffixes`] - the page host followed by each parent label (`net` style: a trailing dot is
//!   already gone, a single label yields one entry).
//! * hide rules from the global list and from every suffix apply; `#@#` exceptions from the global
//!   list and from every suffix remove the selector from the hide set and get their own
//!   `display: revert` line, so a later, more specific rule cannot win.
//! * both lines are emitted in byte order, exactly like `sort.Strings`.
//!
//! The two sentinels are the old `buildCosmeticCss` early returns: an empty (whitespace-only) payload
//! and a payload `encoding/json` rejected. They are part of the response body, so they live here.

use std::collections::{HashMap, HashSet};

use crate::host::normalize_host;

/// `/* DITING: no cosmetic rules loaded */`: the payload was empty or whitespace.
pub const NO_RULES: &str = "/* DITING: no cosmetic rules loaded */";

/// `/* DITING: invalid cosmetic rules */`: `json.Unmarshal` rejected the payload.
pub const INVALID_RULES: &str = "/* DITING: invalid cosmetic rules */";

/// One `domains` entry: the `#?#` selectors and the `#@#` exceptions scoped to that domain.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct DomainRules {
    pub hide: Vec<String>,
    pub exception: Vec<String>,
}

/// The decoded `cosmeticRuleSet`.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Rules {
    pub global_hide: Vec<String>,
    pub global_exception: Vec<String>,
    pub domains: HashMap<String, DomainRules>,
}

/// What `SetCosmeticRules` received, after `strings.TrimSpace` and `json.Unmarshal`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuleSet {
    /// The payload was empty or whitespace: `cosmeticRulesEmpty()` is true, injection is skipped.
    Empty,
    /// The payload was not JSON this shape: injection still runs, the stylesheet is the sentinel.
    Invalid,
    /// A decoded rule set.
    Loaded(Rules),
}

impl RuleSet {
    /// `cosmeticRulesEmpty`: only an empty payload counts. An invalid one must still inject, because
    /// the `<link>` tag does not depend on the rules.
    pub fn is_empty(&self) -> bool {
        matches!(self, RuleSet::Empty)
    }

    /// `buildCosmeticCss`: the stylesheet for one page hostname.
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

        // Walk from the page host up to its parents, so a rule scoped to `example.com` also applies
        // on `ads.example.com`.
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

/// `hostSuffixes`: the host followed by each parent domain, e.g.
/// `["ads.example.com", "example.com", "com"]`.
///
/// The host is normalized first (the rule domains are stored normalized), and the walk stops at a
/// trailing dot or when no dot is left. An empty host yields no suffixes.
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
