use std::slice;

use crate::filter::{FailureReport, Filter};
use crate::payload::encode_report;

pub const ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_mitm_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn diting_mitm_new() -> *mut Filter {
    Box::into_raw(Box::new(Filter::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_mitm_free(handle: *mut Filter) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_mitm_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_mitm_is_uid_allowed(handle: *const Filter, uid: i64) -> u32 {
    match handle.as_ref() {
        Some(filter) if filter.is_uid_allowed(uid) => 1,
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_mitm_has_allowed_uids(handle: *const Filter) -> u32 {
    match handle.as_ref() {
        Some(filter) if filter.has_allowed_uids() => 1,
        _ => 0,
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_mitm_clear(handle: *const Filter) {
    if let Some(filter) = handle.as_ref() {
        filter.clear_blacklist();
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_mitm_blacklist_count(handle: *const Filter, now_ms: i64) -> u32 {
    match handle.as_ref() {
        Some(filter) => filter.blacklist_count(now_ms).min(u32::MAX as usize) as u32,
        None => 0,
    }
}

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

unsafe fn write_payload(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = bytes.into_boxed_slice();
    *out_len = boxed.len();
    *out = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

#[cfg(test)]
mod tests;
