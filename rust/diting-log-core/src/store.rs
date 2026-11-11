//! `RuntimeLogStore`'s pure half: which files a capture keeps, which ones a trim deletes, and the
//! export document the developer reads.
//!
//! The directory, `File.listFiles()`, `readText()`/`delete()` and the `SimpleDateFormat` stamps stay
//! in Kotlin; the predicate, the ordering, the caps and the fixed document text live here, so
//! "newest three files" and the export header cannot drift apart.

/// Hard cap per file, then the oldest file is dropped: a stuck loop must not fill the disk.
///
/// `capture` counts the budget in UTF-16 code units (Kotlin's `String.length`), not bytes.
pub const MAX_FILE_BYTES: i64 = 2 * 1024 * 1024;

/// Files kept on disk; the rest is deleted by a trim.
pub const MAX_FILES: usize = 3;

const LOG_SUFFIX: &str = ".log";
const RULE_WIDTH: usize = 80;
const TITLE_PREFIX: &str = "                 DITING RUNTIME LOGS EXPORT (";
const EXPORTED_LABEL: &str = "                 Exported: ";
/// Stands in for a file the exporter could not read.
pub const UNREADABLE: &str = "(无法读取该文件)";
const CRASH_TITLE: &str = "---- 系统 crash 缓冲区 ----";

/// One directory entry, as `File.listFiles()` reported it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub last_modified: i64,
    pub length: i64,
}

/// One finished capture file, oldest first, with its content when it could be read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Section {
    pub name: String,
    pub content: Option<String>,
}

/// The capture files, newest first, plus how many of them survive a trim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Index {
    pub files: Vec<Entry>,
    /// `files[..keep]` stay on disk; the rest is deleted.
    pub keep: usize,
}

/// `RuntimeLogStore.files` + `trim`: keep the `.log` files, newest first, and name the survivors.
pub fn index(entries: Vec<Entry>) -> Index {
    let mut files: Vec<Entry> = entries
        .into_iter()
        .filter(|entry| entry.name.ends_with(LOG_SUFFIX))
        .collect();
    // `sortedByDescending` is stable, and so is `sort_by`: equal stamps keep the listing order.
    files.sort_by_key(|entry| std::cmp::Reverse(entry.last_modified));
    let keep = files.len().min(MAX_FILES);
    Index { files, keep }
}

/// Total size of the listing; the caller decides what "too big" means.
pub fn total_bytes(files: &[Entry]) -> i64 {
    files
        .iter()
        .fold(0i64, |sum, file| sum.saturating_add(file.length))
}

/// `RuntimeLogStore.read`: the export document, or None when there is nothing to export.
///
/// `exported_at` is injected (the Kotlin side formats it), and so is the crash tail: reading
/// `logcat -b crash` is I/O. The crash section is appended even without a file, because a capture
/// cannot record the death of its own process.
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
        // Three files is still within the cap.
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
        // A crash tail alone is still an export.
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
