#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    NotIndexed,
    Loaded,
    Compiled,
    Failed,
}

impl Outcome {
    pub fn from_tag(tag: u8) -> Option<Self> {
        match tag {
            0 => Some(Self::NotIndexed),
            1 => Some(Self::Loaded),
            2 => Some(Self::Compiled),
            3 => Some(Self::Failed),
            _ => None,
        }
    }

    pub fn tag(self) -> u8 {
        match self {
            Self::NotIndexed => 0,
            Self::Loaded => 1,
            Self::Compiled => 2,
            Self::Failed => 3,
        }
    }

    pub fn usable(self) -> bool {
        matches!(self, Self::Loaded | Self::Compiled)
    }

    fn attempted(self) -> bool {
        matches!(self, Self::Compiled | Self::Failed)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Half {
    pub normal: Outcome,
    pub important: Outcome,
}

impl Half {
    pub fn new(normal: Outcome, important: Outcome) -> Self {
        Self { normal, important }
    }

    pub fn special_rows_only(self) -> bool {
        self.normal.usable() && self.important.usable()
    }

    fn attempted(self) -> bool {
        self.normal.attempted() || self.important.attempted()
    }

    fn failed(self) -> bool {
        self.normal == Outcome::Failed || self.important == Outcome::Failed
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Plan {
    pub block: Half,
    pub allow: Half,
    pub compiled: bool,
    pub settled: bool,
}

pub fn plan(block: Half, allow: Half) -> Plan {
    let compiled = block.attempted() || allow.attempted();
    Plan {
        block,
        allow,
        compiled,
        settled: compiled && !block.failed() && !allow.failed(),
    }
}

pub fn trie_paths(directory_ok: bool, entries: &[(String, bool, i64)]) -> [Option<String>; 4] {
    let mut paths: [Option<String>; 4] = Default::default();
    if !directory_ok {
        return paths;
    }
    for (index, (path, exists, length)) in entries.iter().take(4).enumerate() {
        if *exists && *length > 0 {
            paths[index] = Some(path.clone());
        }
    }
    paths
}

pub fn app_allowlist(entries: Vec<(String, Vec<String>)>) -> Vec<(String, Vec<String>)> {
    let mut result: Vec<(String, Vec<String>)> = Vec::with_capacity(entries.len());
    for (package, domains) in entries {
        let mut seen: Vec<String> = Vec::with_capacity(domains.len());
        for domain in domains {
            let trimmed = domain.trim();
            if trimmed.is_empty() {
                continue;
            }
            if !seen.iter().any(|existing| existing == trimmed) {
                seen.push(trimmed.to_string());
            }
        }
        if seen.is_empty() || package.trim().is_empty() {
            continue;
        }
        result.push((package, seen));
    }
    result
}

pub type TableCounts = Option<(i64, i64, i64)>;

pub fn fingerprint(parts: &[(String, TableCounts)]) -> String {
    parts
        .iter()
        .map(|(table, counts)| match counts {
            None => format!("{table}:-"),
            Some((rows, first, second)) => format!("{table}:{rows}:{first}:{second}"),
        })
        .collect::<Vec<String>>()
        .join("|")
}

pub fn rewrite_rules(rows: Vec<(String, String)>) -> Vec<(String, String)> {
    let mut result: Vec<(String, String)> = Vec::with_capacity(rows.len());
    for (pattern, target) in rows {
        let pattern = pattern.trim();
        let target = target.trim();
        if pattern.is_empty() || target.is_empty() {
            continue;
        }
        if result.iter().any(|(existing, _)| existing == pattern) {
            continue;
        }
        result.push((pattern.to_string(), target.to_string()));
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn files(paths: &[(&str, bool, i64)]) -> Vec<(String, bool, i64)> {
        paths
            .iter()
            .map(|(path, exists, length)| ((*path).to_string(), *exists, *length))
            .collect()
    }

    #[test]
    fn the_stamp_is_only_refreshed_after_a_compile_without_failures() {
        let loaded = plan(
            Half::new(Outcome::Loaded, Outcome::Loaded),
            Half::new(Outcome::Loaded, Outcome::Loaded),
        );
        assert!(!loaded.compiled);
        assert!(!loaded.settled);
        assert!(loaded.block.special_rows_only());

        let compiled = plan(
            Half::new(Outcome::Compiled, Outcome::Loaded),
            Half::new(Outcome::Loaded, Outcome::Loaded),
        );
        assert!(compiled.compiled);
        assert!(compiled.settled);

        let failed = plan(
            Half::new(Outcome::Compiled, Outcome::Loaded),
            Half::new(Outcome::Failed, Outcome::Loaded),
        );
        assert!(failed.compiled);
        assert!(!failed.settled);
        assert!(!failed.allow.special_rows_only());
    }

    #[test]
    fn a_half_needs_both_files_before_only_special_rows_are_read() {
        assert!(Half::new(Outcome::Compiled, Outcome::Loaded).special_rows_only());
        assert!(!Half::new(Outcome::Compiled, Outcome::NotIndexed).special_rows_only());
        assert!(!Half::new(Outcome::Failed, Outcome::Loaded).special_rows_only());
        assert!(!Half::new(Outcome::NotIndexed, Outcome::NotIndexed).special_rows_only());
    }

    #[test]
    fn outcome_tags_round_trip_in_the_kotlin_order() {
        for (tag, outcome) in [
            (0, Outcome::NotIndexed),
            (1, Outcome::Loaded),
            (2, Outcome::Compiled),
            (3, Outcome::Failed),
        ] {
            assert_eq!(Outcome::from_tag(tag), Some(outcome));
            assert_eq!(outcome.tag(), tag);
        }
        assert_eq!(Outcome::from_tag(4), None);
        assert!(Outcome::Loaded.usable());
        assert!(Outcome::Compiled.usable());
        assert!(!Outcome::NotIndexed.usable());
        assert!(!Outcome::Failed.usable());
    }

    #[test]
    fn a_trie_path_needs_a_non_empty_file() {
        let entries = files(&[
            ("/files/rule-index/domain/block.trie", true, 100),
            ("/files/rule-index/domain/block.important.trie", true, 0),
            ("/files/rule-index/domain/allow.trie", false, 0),
            ("/files/rule-index/domain/allow.important.trie", true, 7),
        ]);
        assert_eq!(
            trie_paths(true, &entries),
            [
                Some("/files/rule-index/domain/block.trie".to_string()),
                None,
                None,
                Some("/files/rule-index/domain/allow.important.trie".to_string()),
            ]
        );
        assert_eq!(trie_paths(false, &entries), [None, None, None, None]);
    }

    #[test]
    fn the_app_allowlist_is_trimmed_deduplicated_and_ordered() {
        let entries = vec![
            (
                "com.a".to_string(),
                vec![
                    " example.com ".to_string(),
                    "example.com".into(),
                    "  ".into(),
                ],
            ),
            ("com.empty".to_string(), vec!["".to_string()]),
            ("  ".to_string(), vec!["kept.example".to_string()]),
            (
                "com.b".to_string(),
                vec!["b.example".to_string(), "a.example".to_string()],
            ),
        ];
        assert_eq!(
            app_allowlist(entries),
            vec![
                ("com.a".to_string(), vec!["example.com".to_string()]),
                (
                    "com.b".to_string(),
                    vec!["b.example".into(), "a.example".into()]
                ),
            ]
        );
    }

    #[test]
    fn the_fingerprint_line_matches_the_dao() {
        let parts = vec![
            ("block_rule".to_string(), Some((10, 55, 9))),
            ("block_rule_source".to_string(), Some((12, 60, 12))),
            ("missing_table".to_string(), None),
        ];
        assert_eq!(
            fingerprint(&parts),
            "block_rule:10:55:9|block_rule_source:12:60:12|missing_table:-"
        );
    }

    #[test]
    fn rewrite_rules_keep_the_oldest_row_per_pattern() {
        let rows = vec![
            (" ads.example.com ".to_string(), " 0.0.0.0 ".to_string()),
            ("ads.example.com".to_string(), "1.1.1.1".to_string()),
            ("".to_string(), "0.0.0.0".to_string()),
            ("blank.target".to_string(), "  ".to_string()),
            ("b.example".to_string(), "::".to_string()),
        ];
        assert_eq!(
            rewrite_rules(rows),
            vec![
                ("ads.example.com".to_string(), "0.0.0.0".to_string()),
                ("b.example".to_string(), "::".to_string()),
            ]
        );
    }
}
