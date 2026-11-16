//! Streaming document parse: the same classification as [`crate::document::parse_document`], but the
//! result is handed to the caller one bounded chunk at a time as the existing DRC1 binary payload.
//!
//! A whole-document parse of a large subscription builds every `ParsedRule` at once and hands the
//! caller one big payload; the Dart side then rebuilds every rule object and (before this) also a
//! whole-document JSON plan. For a multi-megabyte subscription those full copies are what push the
//! process to its memory ceiling. This module keeps the working set flat: it walks the document
//! chunk by chunk and each [`StreamParse::next_chunk`] returns only that chunk's rules.
//!
//! Cross-line state is preserved without holding the whole document in rule form:
//! * `$badfilter` rules are collected in a cheap pre-scan (only lines that contain the modifier are
//!   parsed) so a rule disabled by a later line is still removed, exactly like the whole-document
//!   parse. Like the original, it removes only `block` / `allow` / `rewrite` rules — url and
//!   cosmetic families are never badfiltered.
//! * Duplicates are collapsed within a chunk. Across chunks the import SQL's `WHERE NOT EXISTS`
//!   still prevents a duplicate row, so the stored rule set matches the whole-document parse; the
//!   reported duplicate count only counts within-chunk repeats (it is a diagnostic, never stored).

use std::collections::HashSet;
use std::ptr;

use crate::document::parse_categorized_line;
use crate::ffi::{encode, into_buffer};
use crate::keys::{allow_key_of, block_key_of, rewrite_key_of, url_key};
use crate::models::CategorizedRules;

/// Parses `text` in chunks of at most [`Self::chunk_lines`] lines. The text is owned (one copy) so a
/// chunk slice borrows from it without re-scanning; the parser cursor only moves forward.
pub struct StreamParse {
    text: String,
    cursor: usize,
    chunk_lines: usize,
    badfilter_keys: HashSet<String>,
    done: bool,
}

impl StreamParse {
    /// Scans `text` for `$badfilter` keys once, then is ready to yield chunks.
    pub fn new(text: String, chunk_lines: usize) -> Self {
        let badfilter_keys = scan_badfilter_keys(&text);
        Self {
            text,
            cursor: 0,
            chunk_lines: chunk_lines.max(1),
            badfilter_keys,
            done: false,
        }
    }

    /// The next chunk's rules, or `None` once the document is exhausted.
    pub fn next_rules(&mut self) -> Option<CategorizedRules> {
        if self.done {
            return None;
        }
        let mut block_rules = Vec::new();
        let mut allow_rules = Vec::new();
        let mut rewrite_rules = Vec::new();
        let mut url_block_rules = Vec::new();
        let mut url_allow_rules = Vec::new();
        let mut cosmetic_rules = Vec::new();
        let mut seen_block = HashSet::new();
        let mut seen_allow = HashSet::new();
        let mut seen_rewrite = HashSet::new();
        let mut seen_url_block = HashSet::new();
        let mut seen_url_allow = HashSet::new();
        let mut seen_cosmetic = HashSet::new();

        let mut total_lines = 0u32;
        let mut duplicate_count = 0u32;
        let mut invalid_count = 0u32;
        let mut unsupported_count = 0u32;
        let mut ignored_count = 0u32;
        let mut badfiltered_count = 0u32;

        let mut lines_in_chunk = 0usize;
        let mut parsed_any = false;
        while lines_in_chunk < self.chunk_lines {
            let Some((start, end)) = self.take_line() else {
                self.done = true;
                break;
            };
            parsed_any = true;
            lines_in_chunk += 1;
            total_lines += 1;

            let classified = parse_categorized_line(&self.text[start..end]);
            invalid_count += classified.invalid_count;
            unsupported_count += classified.unsupported_count;
            ignored_count += classified.ignored_count;
            // `classified.badfilter_keys` are intentionally ignored here: the pre-scan already has
            // every key from the whole document, including lines later in the file.

            for rule in classified.block_rules {
                let key = block_key_of(&rule);
                if self.badfilter_keys.contains(&key) {
                    badfiltered_count += 1;
                    continue;
                }
                if !seen_block.insert(key) {
                    duplicate_count += 1;
                    continue;
                }
                block_rules.push(rule);
            }
            for rule in classified.allow_rules {
                let key = allow_key_of(&rule);
                if self.badfilter_keys.contains(&key) {
                    badfiltered_count += 1;
                    continue;
                }
                if !seen_allow.insert(key) {
                    duplicate_count += 1;
                    continue;
                }
                allow_rules.push(rule);
            }
            for rule in classified.rewrite_rules {
                let key = rewrite_key_of(&rule);
                if self.badfilter_keys.contains(&key) {
                    badfiltered_count += 1;
                    continue;
                }
                if !seen_rewrite.insert(key) {
                    duplicate_count += 1;
                    continue;
                }
                rewrite_rules.push(rule);
            }
            // Url and cosmetic families are never badfiltered (mirrors `parse_document`), so only
            // within-chunk dedupe applies.
            for rule in classified.url_block_rules {
                let key = url_key("url_block", &rule.pattern, rule.app_scope.as_deref());
                if !seen_url_block.insert(key) {
                    duplicate_count += 1;
                    continue;
                }
                url_block_rules.push(rule);
            }
            for rule in classified.url_allow_rules {
                let key = url_key("url_allow", &rule.pattern, rule.app_scope.as_deref());
                if !seen_url_allow.insert(key) {
                    duplicate_count += 1;
                    continue;
                }
                url_allow_rules.push(rule);
            }
            for rule in classified.cosmetic_rules {
                let key = format!(
                    "cosmetic:{}:{}:{}",
                    rule.domain, rule.selector, rule.is_exception
                );
                if !seen_cosmetic.insert(key) {
                    duplicate_count += 1;
                    continue;
                }
                cosmetic_rules.push(rule);
            }
        }

        if !parsed_any {
            return None;
        }
        Some(CategorizedRules {
            block_rules,
            allow_rules,
            rewrite_rules,
            url_block_rules,
            url_allow_rules,
            cosmetic_rules,
            duplicate_count,
            invalid_count,
            unsupported_count,
            ignored_count,
            badfiltered_count,
            total_lines,
        })
    }

    /// The next chunk encoded as a DRC1 payload, or `None` once the document is exhausted.
    pub fn next_chunk(&mut self) -> Option<Vec<u8>> {
        self.next_rules().map(|rules| encode(&rules))
    }

    /// Next `\n`-delimited line's byte range, or `None` when the document is exhausted. Mirrors
    /// `str::split('\n')`: a trailing newline yields a final empty segment, and an empty document
    /// yields one empty segment — both are counted so line totals match the whole-document parse.
    fn take_line(&mut self) -> Option<(usize, usize)> {
        let length = self.text.len();
        if self.cursor > length {
            return None;
        }
        let start = self.cursor;
        match self.text.as_bytes()[start..]
            .iter()
            .position(|byte| *byte == b'\n')
        {
            Some(offset) => {
                let end = start + offset;
                self.cursor = end + 1;
                Some((start, end))
            }
            None => {
                self.cursor = length + 1;
                Some((start, length))
            }
        }
    }
}

/// A zero-allocation, case-insensitive substring test for the `badfilter` modifier prefilter.
fn contains_ignore_ascii_case(haystack: &str, needle: &[u8]) -> bool {
    let bytes = haystack.as_bytes();
    needle.len() <= bytes.len()
        && bytes
            .windows(needle.len())
            .any(|window| window.eq_ignore_ascii_case(needle))
}

/// Collects every `$badfilter` key in `text`. Only lines that mention `badfilter` are fully parsed,
/// so the prepass stays close to a byte scan even on a large subscription.
fn scan_badfilter_keys(text: &str) -> HashSet<String> {
    let mut keys = HashSet::new();
    for line in text.split('\n') {
        if contains_ignore_ascii_case(line, b"badfilter") {
            keys.extend(parse_categorized_line(line).badfilter_keys);
        }
    }
    keys
}

// ---------------------------------------------------------------------------------------------
// C ABI: a caller opens a session over the raw document bytes, pulls chunks until null, frees it.
// The document bytes are copied into the session, so the caller may release its buffer right after
// `begin`. Handles are boxed pointers; they are not shared across threads.
// ---------------------------------------------------------------------------------------------

/// # Safety
/// `text` must point to `len` readable bytes (or be null with `len == 0`). Returns `0` when the
/// bytes are not valid UTF-8.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_core_stream_begin(
    text: *const u8,
    len: usize,
    chunk_lines: usize,
) -> u64 {
    let bytes: &[u8] = if text.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(text, len)
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return 0;
    };
    let stream = StreamParse::new(text.to_string(), chunk_lines);
    Box::into_raw(Box::new(stream)) as u64
}

/// Returns the next chunk payload and sets `out_len`; a null return with `*out_len == 0` means the
/// document is exhausted. Release the buffer with [`diting_rule_core_stream_free`].
///
/// # Safety
/// `handle` must come from [`diting_rule_core_stream_begin`] and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_core_stream_next(handle: u64, out_len: *mut usize) -> *mut u8 {
    if out_len.is_null() {
        return ptr::null_mut();
    }
    *out_len = 0;
    if handle == 0 {
        return ptr::null_mut();
    }
    let stream = &mut *(handle as *mut StreamParse);
    match stream.next_chunk() {
        Some(bytes) => {
            let (pointer, length) = into_buffer(bytes);
            *out_len = length;
            pointer
        }
        None => ptr::null_mut(),
    }
}

/// Releases a session opened by [`diting_rule_core_stream_begin`]. Chunk payloads returned by
/// [`diting_rule_core_stream_next`] are released separately with [`crate::ffi::diting_rule_core_free`].
///
/// # Safety
/// `handle` must come from [`diting_rule_core_stream_begin`], released once.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_core_stream_free(handle: u64) {
    if handle == 0 {
        return;
    }
    drop(Box::from_raw(handle as *mut StreamParse));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::document::parse_document;

    fn stream_all(text: &str, chunk_lines: usize) -> CategorizedRules {
        let mut stream = StreamParse::new(text.to_string(), chunk_lines);
        let mut merged = CategorizedRules::default();
        while let Some(chunk) = stream.next_rules() {
            merged.block_rules.extend(chunk.block_rules);
            merged.allow_rules.extend(chunk.allow_rules);
            merged.rewrite_rules.extend(chunk.rewrite_rules);
            merged.url_block_rules.extend(chunk.url_block_rules);
            merged.url_allow_rules.extend(chunk.url_allow_rules);
            merged.cosmetic_rules.extend(chunk.cosmetic_rules);
            merged.duplicate_count += chunk.duplicate_count;
            merged.invalid_count += chunk.invalid_count;
            merged.unsupported_count += chunk.unsupported_count;
            merged.ignored_count += chunk.ignored_count;
            merged.badfiltered_count += chunk.badfiltered_count;
            merged.total_lines += chunk.total_lines;
        }
        merged
    }

    fn sorted_patterns(rules: &[crate::models::ParsedRule]) -> Vec<String> {
        let mut patterns: Vec<String> = rules.iter().map(|rule| rule.pattern.clone()).collect();
        patterns.sort();
        patterns
    }

    #[test]
    fn one_chunk_matches_the_whole_document_parse() {
        let text = "||ads.example.com^\n\
                    @@||safe.example.com^\n\
                    ||rw.example.com^$dnsrewrite=1.2.3.4\n\
                    ||tracker.example.com/pixel.js\n\
                    example.org##.ad\n\
                    ||ads.example.com^\n\
                    ! comment\n\
                    ||broken\n";
        let whole = parse_document(text);
        let streamed = stream_all(text, 1000);
        assert_eq!(
            sorted_patterns(&streamed.block_rules),
            sorted_patterns(&whole.block_rules)
        );
        assert_eq!(
            sorted_patterns(&streamed.allow_rules),
            sorted_patterns(&whole.allow_rules)
        );
        assert_eq!(streamed.rewrite_rules.len(), whole.rewrite_rules.len());
        assert_eq!(streamed.url_block_rules.len(), whole.url_block_rules.len());
        assert_eq!(streamed.cosmetic_rules.len(), whole.cosmetic_rules.len());
        assert_eq!(streamed.duplicate_count, whole.duplicate_count);
        assert_eq!(streamed.invalid_count, whole.invalid_count);
        assert_eq!(streamed.unsupported_count, whole.unsupported_count);
        assert_eq!(streamed.ignored_count, whole.ignored_count);
        assert_eq!(streamed.total_lines, whole.total_lines);
    }

    #[test]
    fn badfilter_removes_a_rule_from_an_earlier_chunk() {
        // The `$badfilter` line lands several chunks after the rule it disables.
        let text = "||ads.example.com^\n||keep.example.com^\n||ads.example.com^$badfilter\n";
        let streamed = stream_all(text, 1);
        assert_eq!(
            sorted_patterns(&streamed.block_rules),
            vec!["keep.example.com"]
        );
        assert_eq!(streamed.badfiltered_count, 1);
    }

    #[test]
    fn url_badfilter_never_removes_url_rules() {
        // Mirrors `parse_document`: url families are excluded from badfilter removal.
        let text = "||tracker.example.com/pixel.js\n\
                    ||tracker.example.com/pixel.js$badfilter\n";
        let whole = parse_document(text);
        let streamed = stream_all(text, 1);
        assert_eq!(streamed.url_block_rules.len(), whole.url_block_rules.len());
        assert_eq!(streamed.url_block_rules.len(), 1);
    }

    #[test]
    fn empty_document_yields_one_empty_segment() {
        let mut stream = StreamParse::new(String::new(), 4);
        let first = stream.next_rules().expect("one empty segment");
        assert_eq!(first.total_lines, 1);
        assert!(stream.next_rules().is_none());
    }
}
