#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Layout {
    pub root: &'static str,
    pub domain: &'static str,
    pub hosts: &'static str,
    pub block: &'static str,
    pub block_important: &'static str,
    pub allow: &'static str,
    pub allow_important: &'static str,
}

const DOMAIN: &str = "domain";
const HOSTS: &str = "hosts";
const BLOCK: &str = "block.trie";
const BLOCK_IMPORTANT: &str = "block.important.trie";
const ALLOW: &str = "allow.trie";
const ALLOW_IMPORTANT: &str = "allow.important.trie";

pub fn layout(dataset: u8) -> Option<Layout> {
    let root = match dataset {
        0 => "rule-index",
        1 => "rule-index/express",
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
        assert_eq!(layout(0).unwrap().root, "rule-index");
        assert_eq!(layout(1).unwrap().root, "rule-index/express");
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
        assert_eq!(layout(2), None);
        assert_eq!(layout(255), None);
    }
}
