//! C ABI surface and the compact binary payload the Dart side decodes.
//!
//! One call per document instead of one per line: a subscription import is tens of thousands of
//! lines, and crossing the FFI boundary per line would cost more than the parse itself.
//!
//! Wire format (all integers little-endian `u32`, strings are `u32 len` + UTF-8 bytes, missing
//! optional strings are `u32::MAX`):
//!
//! ```text
//! magic "DRC1" | abi | total | duplicate | invalid | unsupported | ignored | badfiltered
//! block | allow | rewrite | urlBlock | urlAllow | cosmetic      (record counts)
//! <records in that same order>
//! ```

use crate::document::parse_document;
use crate::models::{
    CategorizedRules, ParsedCosmeticRule, ParsedRewriteRule, ParsedRule, ParsedUrlRule,
};

/// Bumped whenever the payload layout or the parsing semantics change; the Dart loader refuses a
/// library whose value does not match what it was compiled against.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DRC1");
pub(crate) const NONE_LEN: u32 = u32::MAX;

pub(crate) fn write_u32(buffer: &mut Vec<u8>, value: u32) {
    buffer.extend_from_slice(&value.to_le_bytes());
}

pub(crate) fn write_str(buffer: &mut Vec<u8>, value: &str) {
    write_u32(buffer, value.len() as u32);
    buffer.extend_from_slice(value.as_bytes());
}

pub(crate) fn write_opt_str(buffer: &mut Vec<u8>, value: Option<&str>) {
    match value {
        Some(text) => write_str(buffer, text),
        None => write_u32(buffer, NONE_LEN),
    }
}

/// Hands `bytes` to the caller as a pointer/length pair that [`diting_rule_core_free`] can
/// rebuild; shrinking to fit keeps the length enough to reconstruct the allocation.
pub(crate) fn into_buffer(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (pointer, length)
}

fn encode_rule(buffer: &mut Vec<u8>, rule: &ParsedRule) {
    write_str(buffer, &rule.pattern);
    write_str(buffer, &rule.raw_line);
    let mut flags = 0u8;
    if rule.important {
        flags |= 1;
    }
    if rule.app_inverted {
        flags |= 2;
    }
    if rule.is_wildcard {
        flags |= 4;
    }
    if rule.is_regex {
        flags |= 8;
    }
    buffer.push(flags);
    write_opt_str(buffer, rule.app_scope.as_deref());
    write_opt_str(buffer, rule.denyallow.as_deref());
    write_opt_str(buffer, rule.dns_type.as_deref());
}

fn encode_rewrite_rule(buffer: &mut Vec<u8>, rule: &ParsedRewriteRule) {
    write_str(buffer, &rule.pattern);
    write_str(buffer, &rule.raw_line);
    write_str(buffer, &rule.target_type);
    write_str(buffer, &rule.target_value);
}

fn encode_url_rule(buffer: &mut Vec<u8>, rule: &ParsedUrlRule) {
    write_str(buffer, &rule.pattern);
    write_str(buffer, &rule.raw_line);
    let mut flags = 0u8;
    if rule.is_allow {
        flags |= 1;
    }
    if rule.important {
        flags |= 2;
    }
    buffer.push(flags);
    write_opt_str(buffer, rule.app_scope.as_deref());
}

fn encode_cosmetic_rule(buffer: &mut Vec<u8>, rule: &ParsedCosmeticRule) {
    write_str(buffer, &rule.domain);
    write_str(buffer, &rule.selector);
    write_str(buffer, &rule.raw_line);
    buffer.push(u8::from(rule.is_exception));
}

pub fn encode(rules: &CategorizedRules) -> Vec<u8> {
    let records = rules.size();
    let mut buffer = Vec::with_capacity(64 + records * 48);
    write_u32(&mut buffer, MAGIC);
    write_u32(&mut buffer, ABI_VERSION);
    for counter in [
        rules.total_lines,
        rules.duplicate_count,
        rules.invalid_count,
        rules.unsupported_count,
        rules.ignored_count,
        rules.badfiltered_count,
        rules.block_rules.len() as u32,
        rules.allow_rules.len() as u32,
        rules.rewrite_rules.len() as u32,
        rules.url_block_rules.len() as u32,
        rules.url_allow_rules.len() as u32,
        rules.cosmetic_rules.len() as u32,
    ] {
        write_u32(&mut buffer, counter);
    }
    for rule in &rules.block_rules {
        encode_rule(&mut buffer, rule);
    }
    for rule in &rules.allow_rules {
        encode_rule(&mut buffer, rule);
    }
    for rule in &rules.rewrite_rules {
        encode_rewrite_rule(&mut buffer, rule);
    }
    for rule in &rules.url_block_rules {
        encode_url_rule(&mut buffer, rule);
    }
    for rule in &rules.url_allow_rules {
        encode_url_rule(&mut buffer, rule);
    }
    for rule in &rules.cosmetic_rules {
        encode_cosmetic_rule(&mut buffer, rule);
    }
    buffer
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_rule_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill with UTF-8 input. Needed because
/// `dart:ffi` has no allocator of its own; release it with [`diting_rule_core_free`].
#[no_mangle]
pub extern "C" fn diting_rule_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// Parses `len` UTF-8 bytes at `text` and returns a buffer the caller must release with
/// [`diting_rule_core_free`]. `out_len` receives the buffer length; a null return means the input
/// was not valid UTF-8 (the Dart caller turns that into an error).
///
/// # Safety
/// `text` must point to `len` readable bytes and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_core_parse(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    *out_len = 0;
    let bytes: &[u8] = if text.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(text, len)
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return std::ptr::null_mut();
    };
    let (pointer, length) = into_buffer(encode(&parse_document(text)));
    *out_len = length;
    pointer
}

/// Releases a buffer returned by [`diting_rule_core_parse`].
///
/// # Safety
/// `pointer`/`len` must be exactly what the parse call returned, released once.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_core_free(pointer: *mut u8, len: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, len, len));
}
