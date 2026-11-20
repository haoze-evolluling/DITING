pub const MAX_FILE_BYTES: i64 = 2 * 1024 * 1024;

pub const MAX_FILES: usize = 3;

const LOG_SUFFIX: &str = ".log";
const RULE_WIDTH: usize = 80;
const TITLE_PREFIX: &str = "                 DITING RUNTIME LOGS EXPORT (";
const EXPORTED_LABEL: &str = "                 Exported: ";
pub const UNREADABLE: &str = "(无法读取该文件)";
const CRASH_TITLE: &str = "---- 系统 crash 缓冲区 ----";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub last_modified: i64,
    pub length: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Section {
    pub name: String,
    pub content: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Index {
    pub files: Vec<Entry>,
    pub keep: usize,
}

pub fn index(entries: Vec<Entry>) -> Index {
    let mut files: Vec<Entry> = entries
        .into_iter()
        .filter(|entry| entry.name.ends_with(LOG_SUFFIX))
        .collect();
    files.sort_by_key(|entry| std::cmp::Reverse(entry.last_modified));
    let keep = files.len().min(MAX_FILES);
    Index { files, keep }
}

pub fn total_bytes(files: &[Entry]) -> i64 {
    files
        .iter()
        .fold(0i64, |sum, file| sum.saturating_add(file.length))
}

pub fn document(sections: &[Section], crash: &str, exported_at: &str) -> Option<String> {
    let crash = crash.trim_end_matches('\n');
    if sections.is_empty() && crash.is_empty() {
        return None;
    }
    let rule = "=".repeat(RULE_WIDTH);
    let mut bodies: Vec<String> = sections
        .iter()
        .map(|section| {
            let content = section.content.as_deref().unwrap_or(UNREADABLE);
            format!("---- {} ----\n{content}", section.name)
        })
        .collect();
    if !crash.is_empty() {
        bodies.push(format!("{CRASH_TITLE}\n{crash}"));
    }
    Some(format!(
        "{rule}\n{TITLE_PREFIX}{} FILE(S))\n{EXPORTED_LABEL}{exported_at}\n{rule}\n\n{}",
        sections.len(),
        bodies.join("\n\n"),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(name: &str, last_modified: i64) -> Entry {
        Entry {
            name: name.to_string(),
            last_modified,
            length: 100,
        }
    }

    #[test]
    fn only_log_files_survive_newest_first() {
        let listing = vec![
            entry("runtime-20260101-000000.log", 10),
            entry(".capture", 99),
            entry("runtime-20260103-000000.log", 30),
            entry("notes.txt", 50),
            entry("runtime-20260102-000000.log", 20),
        ];
        let indexed = index(listing);
        assert_eq!(
            indexed
                .files
                .iter()
                .map(|file| file.name.as_str())
                .collect::<Vec<_>>(),
            vec![
                "runtime-20260103-000000.log",
                "runtime-20260102-000000.log",
                "runtime-20260101-000000.log",
            ]
        );
        assert_eq!(indexed.keep, 3);
        assert_eq!(total_bytes(&indexed.files), 300);
    }

    #[test]
    fn a_trim_keeps_the_newest_three_and_deletes_the_rest() {
        let listing: Vec<Entry> = (0..5)
            .map(|index| entry(&format!("runtime-{index}.log"), index as i64))
            .collect();
        let indexed = index(listing);
        assert_eq!(indexed.keep, MAX_FILES);
        assert_eq!(indexed.files.len(), 5);
        let deleted: Vec<&str> = indexed.files[indexed.keep..]
            .iter()
            .map(|file| file.name.as_str())
            .collect();
        assert_eq!(deleted, vec!["runtime-1.log", "runtime-0.log"]);
    }

    #[test]
    fn equal_stamps_keep_the_listing_order() {
        let listing = vec![entry("a.log", 7), entry("b.log", 7), entry("c.log", 7)];
        let indexed = index(listing);
        assert_eq!(
            indexed
                .files
                .iter()
                .map(|file| file.name.as_str())
                .collect::<Vec<_>>(),
            vec!["a.log", "b.log", "c.log"]
        );
    }

    #[test]
    fn nothing_to_export_answers_none() {
        assert_eq!(document(&[], "", "2026-01-01 00:00:00"), None);
        assert!(document(&[], "*** *** ***\npid: 1", "2026-01-01 00:00:00").is_some());
    }

    #[test]
    fn the_document_wraps_the_files_and_the_crash_buffer() {
        let sections = vec![
            Section {
                name: "runtime-20260101-000000.log".into(),
                content: Some("first\nline".into()),
            },
            Section {
                name: "runtime-20260102-000000.log".into(),
                content: None,
            },
        ];
        let rule = "=".repeat(RULE_WIDTH);
        let expected = format!(
            "{rule}\n{TITLE_PREFIX}2 FILE(S))\n{EXPORTED_LABEL}2026-01-02 03:04:05\n{rule}\n\n\
---- runtime-20260101-000000.log ----\nfirst\nline\n\n\
---- runtime-20260102-000000.log ----\n{UNREADABLE}\n\n\
{CRASH_TITLE}\n*** *** ***\npid: 1",
        );
        assert_eq!(
            document(&sections, "*** *** ***\npid: 1\n", "2026-01-02 03:04:05").as_deref(),
            Some(expected.as_str())
        );
    }

    #[test]
    fn one_file_without_a_crash_has_no_trailing_section() {
        let sections = vec![Section {
            name: "runtime.log".into(),
            content: Some("only".into()),
        }];
        let text = document(&sections, "", "stamp").unwrap();
        assert!(text.ends_with("---- runtime.log ----\nonly"));
        assert!(text.contains("(1 FILE(S))"));
        assert!(!text.contains(CRASH_TITLE));
    }
}
