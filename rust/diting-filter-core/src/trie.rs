use std::collections::HashMap;

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

#[derive(Debug, Default)]
pub struct DomainTrie {
    root: Node,
    size: usize,
}

impl DomainTrie {
    pub fn new() -> Self {
        Self::default()
    }

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

    pub fn match_domain(&self, domain: &str) -> Option<u32> {
        // 空树直接短路：每次查询要查四棵树，其中常有三棵是空的，
        // 原来的 `collect::<Vec<&str>>()` 会让它们照样付一次堆分配。
        if domain.is_empty() || self.root.children.is_empty() {
            return None;
        }
        match_node(&self.root, domain.rsplit('.'))
    }

    pub fn size(&self) -> usize {
        self.size
    }
}

/// 自右向左逐标签下降。`RSplit` 是 `Clone` 的，回溯时可以直接复制迭代器，全程零分配。
fn match_node<'a, I>(node: &Node, labels: I) -> Option<u32>
where
    I: Iterator<Item = &'a str> + Clone,
{
    if let Some(terminal) = node.terminal {
        if !terminal.exact_only {
            return Some(terminal.rule);
        }
    }
    let mut rest = labels;
    let Some(label) = rest.next() else {
        return node.terminal.map(|terminal| terminal.rule);
    };

    // 精确标签优先于同级通配。
    if let Some(child) = node.children.get(label) {
        if let Some(hit) = match_node(child, rest.clone()) {
            return Some(hit);
        }
    }
    if let Some(child) = node.children.get("*") {
        if let Some(hit) = match_node(child, rest) {
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
        assert_eq!(trie.match_domain("sub.ad.com"), Some(0));
    }

    #[test]
    fn exact_labels_beat_wildcards_at_the_same_level() {
        let trie = trie(&[("*.ad.com", false), ("banner.ad.com", true)]);
        assert_eq!(trie.match_domain("banner.ad.com"), Some(1));
        assert_eq!(trie.match_domain("other.ad.com"), Some(0));
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
