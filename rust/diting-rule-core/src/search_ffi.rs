//! C ABI for the rule-list search index (`filteredRulesProvider` on the rules page).
//!
//! Unlike the parse entry point, this surface is stateful: the rules page builds one index per
//! table snapshot and queries it once per keystroke. Sending the whole table across the boundary on
//! every key would cost more than the Dart filter it replaces, so the handle pattern is used
//! instead:
//!
//! ```text
//! build(rows)  -> u64 handle      (0 = failed, the Dart side keeps its own filter)
//! query(handle, needle) -> hits   (freed with `diting_rule_core_free`)
//! free_index(handle)
//! ```
//!
//! Wire format (all integers little-endian `u32`, strings are `u32 len` + UTF-8 bytes, a missing
//! optional string is `u32::MAX`):
//!
//! ```text
//! build  : magic "DRS1" | abi | rows  | rows * (pattern, target?)
//! result : magic "DRQ1" | abi | hits  | hits * row index
//! ```
//!
//! Every failure returns 0 / null instead of raising: the Dart side then falls back to the Dart
//! filter, so a missing symbol, a stale `.so` or a malformed payload can never break the page.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use crate::ffi::{into_buffer, write_u32, NONE_LEN};
use crate::search::RuleSearchIndex;

/// Layout version of the build/result payloads; the Dart loader refuses a library that does not
/// speak it. Kept separate from [`crate::ffi::ABI_VERSION`] so adding this module does not force a
/// parse fallback on older artifacts (and vice versa).
pub const SEARCH_ABI_VERSION: u32 = 1;

const BUILD_MAGIC: u32 = u32::from_le_bytes(*b"DRS1");
const RESULT_MAGIC: u32 = u32::from_le_bytes(*b"DRQ1");

/// A build payload holds at least two length prefixes per row.
const MIN_ROW_BYTES: usize = 8;

type Index = Arc<RuleSearchIndex>;

/// Process-wide handle table. Handles are opaque to Dart and `0` is never handed out.
static REGISTRY: OnceLock<Mutex<HashMap<u64, Index>>> = OnceLock::new();
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

fn registry() -> &'static Mutex<HashMap<u64, Index>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Registers `index` and returns its handle, or `0` when the table is unusable.
pub fn register(index: RuleSearchIndex) -> u64 {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    match registry().lock() {
        Ok(mut indexes) => {
            indexes.insert(handle, Arc::new(index));
            handle
        }
        Err(_) => 0,
    }
}

/// Runs `body` against the index behind `handle`, or returns `None` for an unknown handle.
fn with_index<R>(handle: u64, body: impl FnOnce(&RuleSearchIndex) -> R) -> Option<R> {
    let index = registry().lock().ok()?.get(&handle).cloned()?;
    Some(body(&index))
}

pub fn unregister(handle: u64) -> bool {
    match registry().lock() {
        Ok(mut indexes) => indexes.remove(&handle).is_some(),
        Err(_) => false,
    }
}

/// Handles currently registered: the tests use it to prove a rebuild and a dispose both release.
#[cfg(test)]
fn live_handles() -> usize {
    registry().lock().map(|indexes| indexes.len()).unwrap_or(0)
}

/// Sequential little-endian reader over the build payload.
struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn u32(&mut self) -> Option<u32> {
        let end = self.offset.checked_add(4)?;
        let slice = self.bytes.get(self.offset..end)?;
        self.offset = end;
        Some(u32::from_le_bytes(slice.try_into().ok()?))
    }

    fn required_str(&mut self) -> Option<&'a str> {
        let length = self.u32()?;
        if length == NONE_LEN {
            return None;
        }
        self.text(length as usize)
    }

    /// `Some(None)` for the `u32::MAX` marker, `Some(Some(text))` for a string, `None` when the
    /// payload is malformed.
    fn optional_str(&mut self) -> Option<Option<&'a str>> {
        let length = self.u32()?;
        if length == NONE_LEN {
            return Some(None);
        }
        Some(Some(self.text(length as usize)?))
    }

    fn text(&mut self, length: usize) -> Option<&'a str> {
        let end = self.offset.checked_add(length)?;
        let slice = self.bytes.get(self.offset..end)?;
        self.offset = end;
        std::str::from_utf8(slice).ok()
    }
}

/// Build payload -> search index. `None` for a truncated, misnumbered or non-UTF-8 payload.
pub fn decode_build_payload(payload: &[u8]) -> Option<RuleSearchIndex> {
    let mut reader = Reader {
        bytes: payload,
        offset: 0,
    };
    if reader.u32()? != BUILD_MAGIC || reader.u32()? != SEARCH_ABI_VERSION {
        return None;
    }
    let rows = reader.u32()? as usize;
    // A row cannot be smaller than its two length prefixes, so a larger count is malformed: this
    // keeps `with_capacity` from reserving a size the payload could never describe.
    if rows > payload.len() / MIN_ROW_BYTES {
        return None;
    }
    let mut index = RuleSearchIndex::with_capacity(rows);
    for _ in 0..rows {
        let pattern = reader.required_str()?;
        let target = reader.optional_str()?;
        index.push(pattern, target);
    }
    Some(index)
}

pub fn encode_hits(hits: &[u32]) -> Vec<u8> {
    let mut buffer = Vec::with_capacity(12 + hits.len() * 4);
    write_u32(&mut buffer, RESULT_MAGIC);
    write_u32(&mut buffer, SEARCH_ABI_VERSION);
    write_u32(&mut buffer, hits.len() as u32);
    for hit in hits {
        write_u32(&mut buffer, *hit);
    }
    buffer
}

/// Borrows the caller's buffer; an empty input is a valid empty slice.
///
/// # Safety
/// `pointer` must be null or point to `len` readable bytes.
unsafe fn input<'a>(pointer: *const u8, len: usize) -> &'a [u8] {
    if pointer.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(pointer, len)
    }
}

/// Sequence number of this file's payload layout; must match `_searchAbiVersion` in
/// `rust_rule_core.dart`.
#[no_mangle]
pub extern "C" fn diting_rule_core_search_abi_version() -> u32 {
    SEARCH_ABI_VERSION
}

/// Builds an index from a build payload and returns its handle, or `0` on any failure.
///
/// # Safety
/// `payload` must point to `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_core_search_build(payload: *const u8, len: usize) -> u64 {
    let built = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let index = decode_build_payload(input(payload, len))?;
        Some(register(index))
    }));
    match built {
        Ok(Some(handle)) if handle != 0 => handle,
        _ => 0,
    }
}

/// Queries `handle` for `needle` and returns a result payload the caller must release with
/// [`crate::ffi::diting_rule_core_free`], or null when the handle is unknown or the call failed.
///
/// # Safety
/// `needle` must point to `needle_len` readable bytes and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_core_search_query(
    handle: u64,
    needle: *const u8,
    needle_len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    *out_len = 0;
    let queried = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let needle = std::str::from_utf8(input(needle, needle_len)).ok()?;
        let hits = with_index(handle, |index| index.matching(needle))?;
        Some(encode_hits(&hits))
    }));
    match queried {
        Ok(Some(buffer)) => {
            let (pointer, length) = into_buffer(buffer);
            *out_len = length;
            pointer
        }
        _ => std::ptr::null_mut(),
    }
}

/// Releases `handle` and its folded rows; returns 1 when it was there, 0 when it was not.
#[no_mangle]
pub extern "C" fn diting_rule_core_search_free_index(handle: u64) -> u32 {
    u32::from(unregister(handle))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build_payload(rows: &[(&str, Option<&str>)]) -> Vec<u8> {
        let mut payload = Vec::new();
        write_u32(&mut payload, BUILD_MAGIC);
        write_u32(&mut payload, SEARCH_ABI_VERSION);
        write_u32(&mut payload, rows.len() as u32);
        for (pattern, target) in rows {
            crate::ffi::write_str(&mut payload, pattern);
            crate::ffi::write_opt_str(&mut payload, *target);
        }
        payload
    }

    fn decode_hits(payload: &[u8]) -> Vec<u32> {
        let mut reader = Reader {
            bytes: payload,
            offset: 0,
        };
        assert_eq!(reader.u32().unwrap(), RESULT_MAGIC);
        assert_eq!(reader.u32().unwrap(), SEARCH_ABI_VERSION);
        let count = reader.u32().unwrap();
        (0..count).map(|_| reader.u32().unwrap()).collect()
    }

    #[test]
    fn payload_round_trip_returns_row_indices() {
        let payload = build_payload(&[
            ("||ads.example.com^", None),
            ("||safe.example.com^", Some("0.0.0.0")),
        ]);
        let index = decode_build_payload(&payload).expect("payload decodes");
        assert_eq!(index.len(), 2);
        assert_eq!(
            decode_hits(&encode_hits(&index.matching("example"))),
            vec![0, 1]
        );
        assert_eq!(
            decode_hits(&encode_hits(&index.matching("0.0.0.0"))),
            vec![1]
        );
    }

    #[test]
    fn malformed_payloads_are_rejected() {
        let good = build_payload(&[("||ads.example.com^", None)]);
        assert!(decode_build_payload(&good).is_some());

        // Wrong magic, wrong abi, truncated record, count larger than the payload can describe.
        let mut wrong_magic = good.clone();
        wrong_magic[0] ^= 0xFF;
        assert!(decode_build_payload(&wrong_magic).is_none());

        let mut wrong_abi = good.clone();
        wrong_abi[4] = 0xFF;
        assert!(decode_build_payload(&wrong_abi).is_none());

        assert!(decode_build_payload(&good[..good.len() - 1]).is_none());

        let mut oversized = Vec::new();
        write_u32(&mut oversized, BUILD_MAGIC);
        write_u32(&mut oversized, SEARCH_ABI_VERSION);
        write_u32(&mut oversized, u32::MAX);
        assert!(decode_build_payload(&oversized).is_none());
    }

    #[test]
    fn handles_are_released() {
        let before = live_handles();
        let handle = register(RuleSearchIndex::default());
        assert_ne!(handle, 0);
        assert_eq!(live_handles(), before + 1);
        assert_eq!(with_index(handle, |index| index.len()), Some(0));
        assert!(unregister(handle));
        assert_eq!(with_index(handle, |index| index.len()), None);
        assert!(!unregister(handle));
        assert_eq!(live_handles(), before);
    }
}
