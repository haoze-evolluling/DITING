//! `RuleIndexLayout`: where one dataset keeps its DTRI artifacts.
//!
//! The paths are relative to `filesDir`; Kotlin joins them with `File`. They live here so the
//! layout, the stamp check and the Go engine's mmap target cannot disagree about a file name.

/// The artifact names of one dataset, relative to `filesDir` (the root) or to the root itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Layout {
    /// `rule-index` for normal, `rule-index/express` for express, `rule-index/dns` for DNS mode.
    pub root: &'static str,
    /// `domain`, the folder holding the four tries.
    pub domain: &'static str,
    /// `hosts`, kept for path parity with the legacy layout (no artifact is written there).
    pub hosts: &'static str,
    pub block: &'static str,
    pub block_important: &'static str,
    pub allow: &'static str,
    pub allow_important: &'static str,
}

/// The four trie names and the two folders; only [`Layout::root`] varies per dataset.
const DOMAIN: &str = "domain";
const HOSTS: &str = "hosts";
const BLOCK: &str = "block.trie";
const BLOCK_IMPORTANT: &str = "block.important.trie";
const ALLOW: &str = "allow.trie";
const ALLOW_IMPORTANT: &str = "allow.important.trie";

/// `RuleDataset` tags: NORMAL (0), EXPRESS (1), DNS_MODE (2).
pub fn layout(dataset: u8) -> Option<Layout> {
    let root = match dataset {
        0 => "rule-index",
        1 => "rule-index/express",
        2 => "rule-index/dns",
        _ => return None,
    };
    Some(Layout {
        root,
        domain: DOMAIN,
        hosts: HOSTS,
        block: BLOCK,
        block_important: BLOCK_IMPORTANT,
        allow: ALLOW,
        allow_important: ALLOW_IMPORTANT,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_dataset_gets_its_own_root() {
        // Every dataset writes its own artifacts under filesDir; sharing a root would make the
        // three rule databases overwrite each other's tries.
        assert_eq!(layout(0).unwrap().root, "rule-index");
        assert_eq!(layout(1).unwrap().root, "rule-index/express");
        assert_eq!(layout(2).unwrap().root, "rule-index/dns");
    }

    #[test]
    fn the_artifact_names_are_the_legacy_ones() {
        let normal = layout(0).unwrap();
        assert_eq!(normal.domain, "domain");
        assert_eq!(normal.hosts, "hosts");
        assert_eq!(normal.block, "block.trie");
        assert_eq!(normal.block_important, "block.important.trie");
        assert_eq!(normal.allow, "allow.trie");
        assert_eq!(normal.allow_important, "allow.important.trie");
        // Only the root differs between datasets, so the tails are safe to share.
        let express = layout(1).unwrap();
        assert_eq!(
            (
                normal.domain,
                normal.hosts,
                normal.block,
                normal.block_important,
                normal.allow,
                normal.allow_important
            ),
            (
                express.domain,
                express.hosts,
                express.block,
                express.block_important,
                express.allow,
                express.allow_important
            )
        );
    }

    #[test]
    fn an_unknown_dataset_is_not_a_layout() {
        assert_eq!(layout(3), None);
        assert_eq!(layout(255), None);
    }
}
