//! `DomainTrie`: the reversed-label trie the Go engine used before the move.
//!
//! Insertion walks the labels of a pattern from the rightmost one (`ads.google.com` becomes
//! `com -> google -> ads`), so a rule that blocks a domain covers every subdomain in one walk.
//! `|domain|` rules land on the same node but are marked exact: they do not inherit downwards.
//!
//! The lookup is the same depth-first walk, with the same tie-breaking: a shorter (higher) suffix
//! that is a plain block wins over a longer exact rule that would have to descend further, and an
//! exact label always beats a `*` child at the same level. Both properties decide *which* rule is
//! reported when several match, so `rule_engine_*.go` tests keep the same `MatchedRule`.

use std::collections::HashMap;

/// What a node remembers when a rule pattern ends there.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Terminal {
    rule: u32,
    exact_only: bool,
}

#[derive(Debug, Default)]
struct Node {
    children: HashMap<Box<str>, Node>,
    terminal: Option<Terminal>,
}

/// Reversed-label trie over plain domain rules.
#[derive(Debug, Default)]
pub struct DomainTrie {
    root: Node,
    size: usize,
}

impl DomainTrie {
    pub fn new() -> Self {
        Self::default()
    }

    /// `DomainTrie.Insert`: the pattern is already normalized by `rule`.
    pub fn insert(&mut self, pattern: &str, rule: u32, exact_only: bool) {
        if pattern.is_empty() {
            return;
        }
        let mut node = &mut self.root;
        for label in pattern.rsplit('.') {
            node = node.children.entry(label.into()).or_default();
        }
        node.terminal = Some(Terminal { rule, exact_only });
        self.size += 1;
    }

    /// `DomainTrie.Match`: the rule index of the first match, if any.
    pub fn match_domain(&self, domain: &str) -> Option<u32> {
        if domain.is_empty() {
            return None;
        }
        let labels: Vec<&str> = domain.split('.').collect();
        match_node(&self.root, &labels, labels.len() as isize - 1)
    }

    /// `DomainTrie.Size`: number of terminal rules stored.
    pub fn size(&self) -> usize {
        self.size
    }
}

fn match_node(node: &Node, labels: &[&str], index: isize) -> Option<u32> {
    // A plain (non-exact) terminal covers every subdomain, so it answers before descending.
    if let Some(terminal) = node.terminal {
        if !terminal.exact_only {
            return Some(terminal.rule);
        }
    }
    if index < 0 {
        return node.terminal.map(|terminal| terminal.rule);
    }

    let label = labels[index as usize];
    if let Some(child) = node.children.get(label) {
        if let Some(hit) = match_node(child, labels, index - 1) {
            return Some(hit);
        }
    }
    // `*` is only consulted after the exact label path failed.
    if let Some(child) = node.children.get("*") {
        if let Some(hit) = match_node(child, labels, index - 1) {
            return Some(hit);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn trie(rules: &[(&str, bool)]) -> DomainTrie {
        let mut trie = DomainTrie::new();
        for (index, (pattern, exact)) in rules.iter().enumerate() {
            trie.insert(pattern, index as u32, *exact);
        }
        trie
    }

    #[test]
    fn subdomains_inherit_but_exact_rules_do_not() {
        let trie = trie(&[("ad.com", false), ("exact.com", true)]);
        assert_eq!(trie.match_domain("ad.com"), Some(0));
        assert_eq!(trie.match_domain("sub.ad.com"), Some(0));
        assert_eq!(trie.match_domain("a.b.c.ad.com"), Some(0));
        assert_eq!(trie.match_domain("exact.com"), Some(1));
        assert_eq!(trie.match_domain("sub.exact.com"), None);
        assert_eq!(trie.match_domain("notad.com"), None);
        assert_eq!(trie.match_domain(""), None);
    }

    #[test]
    fn a_higher_plain_suffix_beats_a_deeper_exact_rule() {
        let trie = trie(&[("ad.com", false), ("sub.ad.com", true)]);
        // `ad.com` is a plain block, so it answers before the walk reaches `sub.ad.com`.
        assert_eq!(trie.match_domain("sub.ad.com"), Some(0));
    }

    #[test]
    fn exact_labels_beat_wildcards_at_the_same_level() {
        let trie = trie(&[("*.ad.com", false), ("banner.ad.com", true)]);
        assert_eq!(trie.match_domain("banner.ad.com"), Some(1));
        assert_eq!(trie.match_domain("other.ad.com"), Some(0));
        // The wildcard label must consume exactly one label.
        assert_eq!(trie.match_domain("deep.other.ad.com"), Some(0));
        assert_eq!(trie.match_domain("ad.com"), None);
    }

    #[test]
    fn later_insertions_win_on_the_same_node() {
        let mut trie = DomainTrie::new();
        trie.insert("ad.com", 0, false);
        trie.insert("ad.com", 1, true);
        assert_eq!(trie.match_domain("ad.com"), Some(1));
        assert_eq!(trie.match_domain("sub.ad.com"), None);
        assert_eq!(trie.size(), 2);
    }
}
