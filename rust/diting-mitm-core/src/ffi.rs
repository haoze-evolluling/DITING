//! The C ABI `android/engine/mitm_filter_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_mitm_abi_version` | ABI number the loader validates |
//! | `diting_mitm_new` | build an empty filter handle |
//! | `diting_mitm_free` | drop a handle and its state |
//! | `diting_mitm_free_bytes` | drop a report payload this library returned |
//! | `diting_mitm_set_allowed_uids` | replace the allow list from a CSV, returns the count |
//! | `diting_mitm_is_uid_allowed` | is this UID allowed to be intercepted |
//! | `diting_mitm_has_allowed_uids` | is any UID allowed |
//! | `diting_mitm_set_bypass_rules` | replace the exclusion patterns from a multi-line text |
//! | `diting_mitm_allows_interception` | the interception decision for one host |
//! | `diting_mitm_record_failure` | count a TLS failure (may blacklist), returns a report |
//! | `diting_mitm_blacklist` | blacklist one host now, returns `1` when it was added |
//! | `diting_mitm_clear` | drop every entry, streak and the persisted file |
//! | `diting_mitm_remove` | forget one host |
//! | `diting_mitm_load_persistent` | read the blacklist file, returns the live entry count |
//! | `diting_mitm_blacklist_count` | live entries, for the UI |
//!
//! Text arguments are UTF-8 byte pairs. A host that is not valid UTF-8 is treated as "not a host":
//! interception is refused (that is the conservative side for a MITM gate) and the stateful calls
//! record nothing. Go strings are byte strings, so this is the one input the old implementation
//! would have accepted; hosts reaching this kernel come from an HTTP `Host` header or a TLS SNI
//! extension, both of which the normalizers already lowercase as UTF-8.
//!
//! A null handle makes every call a no-op, exactly like the other kernels.

use std::slice;

use crate::filter::{FailureReport, Filter};
use crate::payload::encode_report;

/// Must match `mitmFilterABIVersion` in `android/engine/mitm_filter_native.go`.
pub const ABI_VERSION: u32 = 1;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_mitm_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates an empty filter: no allowed UIDs, no bypass pattern, an empty blacklist.
#[no_mangle]
pub extern "C" fn diting_mitm_new() -> *mut Filter {
    Box::into_raw(Box::new(Filter::new()))
}

/// Drops a handle created by [`diting_mitm_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_mitm_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_free(handle: *mut Filter) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Frees a report payload returned by this library.
///
/// # Safety
///
/// `pointer`/`length` must be a pair this library produced and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Replaces the allow list from a CSV and returns how many UIDs it now holds.
///
/// # Safety
///
/// `csv` must be readable for `length` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_set_allowed_uids(
    handle: *const Filter,
    csv: *const u8,
    length: usize,
) -> u32 {
    let Some(filter) = handle.as_ref() else {
        return 0;
    };
    let Some(text) = text(csv, length) else {
        return 0;
    };
    filter.set_allowed_uids_csv(text) as u32
}

/// Reports whether `uid` may be intercepted.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_is_uid_allowed(handle: *const Filter, uid: i64) -> u32 {
    match handle.as_ref() {
        Some(filter) if filter.is_uid_allowed(uid) => 1,
        _ => 0,
    }
}

/// Reports whether any UID is under strict interception.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_has_allowed_uids(handle: *const Filter) -> u32 {
    match handle.as_ref() {
        Some(filter) if filter.has_allowed_uids() => 1,
        _ => 0,
    }
}

/// Replaces the bypass patterns from a multi-line text and returns how many were kept.
///
/// # Safety
///
/// `content` must be readable for `length` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_set_bypass_rules(
    handle: *const Filter,
    content: *const u8,
    length: usize,
) -> u32 {
    let Some(filter) = handle.as_ref() else {
        return 0;
    };
    let Some(text) = text(content, length) else {
        return 0;
    };
    filter.set_bypass_rules(text) as u32
}

/// The interception decision: `1` when the host may be decrypted, `0` when it must pass through.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_allows_interception(
    handle: *const Filter,
    host: *const u8,
    host_len: usize,
    now_ms: i64,
) -> u32 {
    let Some(filter) = handle.as_ref() else {
        return 0;
    };
    let Some(host) = text(host, host_len) else {
        return 0;
    };
    match filter.allows_interception(host, now_ms) {
        true => 1,
        false => 0,
    }
}

/// Counts a TLS failure. The report payload (see [`crate::payload`]) says whether the streak was
/// counted, the streak length and threshold, the normalized host, and — when this call blacklisted
/// the host — the reason, the lifetime and any file write error.
///
/// # Safety
///
/// Text pointers must be readable for their lengths; the out pointers must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_record_failure(
    handle: *const Filter,
    host: *const u8,
    host_len: usize,
    error: *const u8,
    error_len: usize,
    now_ms: i64,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) {
    if payload_out.is_null() || payload_len.is_null() {
        return;
    }
    let empty = FailureReport {
        recorded: false,
        blacklisted: false,
        count: 0,
        threshold: 0,
        host: String::new(),
        blacklist: None,
    };
    let report = match (
        handle.as_ref(),
        text(host, host_len),
        text(error, error_len),
    ) {
        (Some(filter), Some(host), Some(error)) => filter.record_failure(host, error, now_ms),
        _ => empty,
    };
    write_payload(encode_report(&report), payload_out, payload_len);
}

/// Blacklists one host now. Returns `1` when the entry was added, and only then writes a report
/// payload describing the reason and lifetime the caller logs.
///
/// # Safety
///
/// Text pointers must be readable for their lengths; the out pointers must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_blacklist(
    handle: *const Filter,
    host: *const u8,
    host_len: usize,
    reason: *const u8,
    reason_len: usize,
    now_ms: i64,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if payload_out.is_null() || payload_len.is_null() {
        return 0;
    }
    let (Some(filter), Some(host), Some(reason)) = (
        handle.as_ref(),
        text(host, host_len),
        text(reason, reason_len),
    ) else {
        return 0;
    };
    let Some(added) = filter.blacklist(host, reason, now_ms) else {
        return 0;
    };
    let report = FailureReport {
        recorded: false,
        blacklisted: true,
        count: 0,
        threshold: 0,
        host: added.host.clone(),
        blacklist: Some(added),
    };
    write_payload(encode_report(&report), payload_out, payload_len);
    1
}

/// Drops every blacklist entry and failure streak, and truncates the persistent file.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_clear(handle: *const Filter) {
    if let Some(filter) = handle.as_ref() {
        filter.clear_blacklist();
    }
}

/// Forgets one host (blacklist entry and failure streak).
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_remove(
    handle: *const Filter,
    host: *const u8,
    host_len: usize,
) {
    let (Some(filter), Some(host)) = (handle.as_ref(), text(host, host_len)) else {
        return;
    };
    filter.remove_from_blacklist(host);
}

/// Reads the persistent blacklist and remembers the path; returns how many live entries it held.
///
/// # Safety
///
/// `path` must be readable for `path_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_load_persistent(
    handle: *const Filter,
    path: *const u8,
    path_len: usize,
    now_ms: i64,
) -> u32 {
    let (Some(filter), Some(path)) = (handle.as_ref(), text(path, path_len)) else {
        return 0;
    };
    filter.load_persistent(path, now_ms) as u32
}

/// Live blacklist entries at `now_ms`.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_mitm_blacklist_count(handle: *const Filter, now_ms: i64) -> u32 {
    match handle.as_ref() {
        Some(filter) => filter.blacklist_count(now_ms).min(u32::MAX as usize) as u32,
        None => 0,
    }
}

/// Rebuilds a UTF-8 argument; invalid UTF-8 or a null pointer with a length is `None`.
unsafe fn text<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    let bytes = if length == 0 {
        &[][..]
    } else if pointer.is_null() {
        return None;
    } else {
        slice::from_raw_parts(pointer, length)
    };
    std::str::from_utf8(bytes).ok()
}

/// Hands a `Vec<u8>` to the caller; the length travels with the pointer so Go can rebuild the same
/// allocation in [`diting_mitm_free_bytes`].
unsafe fn write_payload(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = bytes.into_boxed_slice();
    *out_len = boxed.len();
    *out = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

#[cfg(test)]
mod tests;
