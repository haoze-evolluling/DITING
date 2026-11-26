use std::collections::HashSet;
use std::ptr;

use crate::document::parse_categorized_line;
use crate::ffi::{encode, into_buffer};
use crate::hierarchy::{is_plain_domain_rule, PlainAncestors};
use crate::keys::{allow_key_of, block_key_of, rewrite_key_of, url_key};
use crate::models::CategorizedRules;

pub struct StreamParse {
    text: String,
    cursor: usize,
    chunk_lines: usize,
    badfilter_keys: HashSet<String>,
    plain_ancestors: PlainAncestors,
    done: bool,
}

impl StreamParse {
    pub fn new(text: String, chunk_lines: usize) -> Self {
        let (badfilter_keys, plain_ancestors) = scan_plain_blocks(&text);
        Self {
            text,
            cursor: 0,
            chunk_lines: chunk_lines.max(1),
            badfilter_keys,
            plain_ancestors,
            done: false,
        }
    }

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
                if self.plain_ancestors.covers(&rule) {
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

    pub fn next_chunk(&mut self) -> Option<Vec<u8>> {
        self.next_rules().map(|rules| encode(&rules))
    }

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

/// 一次预扫描收集 badfilter 键与普通屏蔽规则的父域名集合。
/// 分块解析无法回看后续分块，所以层级去重必须依赖整篇文档的预扫描。
fn scan_plain_blocks(text: &str) -> (HashSet<String>, PlainAncestors) {
    let mut keys = HashSet::new();
    let mut plain_rules: Vec<(bool, String, String)> = Vec::new();
    for line in text.split('\n') {
        let classified = parse_categorized_line(line);
        keys.extend(classified.badfilter_keys);
        for rule in &classified.block_rules {
            if is_plain_domain_rule(rule) {
                plain_rules.push((rule.important, rule.pattern.clone(), block_key_of(rule)));
            }
        }
    }
    let mut ancestors = PlainAncestors::default();
    for (important, pattern, key) in plain_rules {
        if !keys.contains(&key) {
            ancestors.insert_pattern(important, &pattern);
        }
    }
    (keys, ancestors)
}

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
    fn hierarchy_dedup_matches_the_document_across_chunks() {
        let text = "||wechat.qq.com^\n||qq.com^\n||mail.wechat.qq.com^\n||other.com^\n";
        let whole = parse_document(text);
        let streamed = stream_all(text, 1);
        assert_eq!(
            sorted_patterns(&streamed.block_rules),
            sorted_patterns(&whole.block_rules)
        );
        assert_eq!(streamed.duplicate_count, whole.duplicate_count);
    }

    #[test]
    fn a_badfiltered_parent_does_not_cover_later_chunks() {
        let text = "||qq.com^\n||qq.com^$badfilter\n||wechat.qq.com^\n";
        let streamed = stream_all(text, 1);
        assert_eq!(
            sorted_patterns(&streamed.block_rules),
            vec!["wechat.qq.com"]
        );
        assert_eq!(streamed.badfiltered_count, 1);
        assert_eq!(streamed.duplicate_count, 0);
    }

    #[test]
    fn badfilter_removes_a_rule_from_an_earlier_chunk() {
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
