//! The C ABI `android/engine/request_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_request_abi_version` | ABI number the loader validates |
//! | `diting_request_new` | rule set payload in, handle out |
//! | `diting_request_match` | one scheme/host/path in, one decision payload out (handle-scoped) |
//! | `diting_request_close` | drop a handle |
//! | `diting_request_free_bytes` | drop a payload this library returned |
//!
//! The handle exists because this filter runs per HTTP request: the normalized rule set is built once
//! per settings change and walked without re-encoding. It is immutable, so a match needs no lock.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;

use crate::payload::{build_rules, decode_match, decode_rules, encode_match};
use crate::rules::Rule;

/// Must match `requestABIVersion` in `android/engine/request_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;
const STATUS_PANIC: u32 = 3;

/// The kernel's handle: one normalized, immutable rule set.
pub struct RuleSet {
    rules: Vec<Rule>,
}

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_request_abi_version() -> u32 {
    ABI_VERSION
}

/// Builds a rule set and hands out a handle.
///
/// The payload is never invalid from Go (it is built from a decoded JSON list), so a failure here
/// means a broken caller: the handle stays null.
///
/// # Safety
///
/// `rules` must be readable for `rules_len` bytes and `handle_out` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_request_new(
    rules: *const u8,
    rules_len: usize,
    handle_out: *mut *mut RuleSet,
) -> u32 {
    if handle_out.is_null() || (rules.is_null() && rules_len != 0) {
        return STATUS_BAD_ARGUMENT;
    }
    *handle_out = std::ptr::null_mut();
    let payload = if rules_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(rules, rules_len)
    };
    let Some(decoded) = decode_rules(payload) else {
        return STATUS_BAD_PAYLOAD;
    };
    let built = catch_unwind(AssertUnwindSafe(|| build_rules(&decoded)));
    match built {
        Ok(rules) => {
            *handle_out = Box::into_raw(Box::new(RuleSet { rules }));
            STATUS_OK
        }
        Err(_) => STATUS_PANIC,
    }
}

/// Decides one request; the returned payload is `matched | blocked | pattern | domain host`.
///
/// # Safety
///
/// `handle` must come from [`diting_request_new`] and not have been closed; `request` must be
/// readable for `request_len` bytes and `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_request_match(
    handle: *const RuleSet,
    request: *const u8,
    request_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if handle.is_null() || out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    if request.is_null() && request_len != 0 {
        return STATUS_BAD_ARGUMENT;
    }
    let payload = if request_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(request, request_len)
    };
    let Some(decoded) = decode_match(payload) else {
        return STATUS_BAD_PAYLOAD;
    };
    let rules = &(*handle).rules;
    let encoded = match catch_unwind(AssertUnwindSafe(|| encode_match(rules, &decoded))) {
        Ok(encoded) => encoded,
        Err(_) => return STATUS_PANIC,
    };
    // A boxed slice so the allocation's capacity is its length: Go frees it with that length.
    let mut boxed = encoded.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

/// Drops a handle from [`diting_request_new`].
///
/// # Safety
///
/// `handle` must come from that call and must not be closed twice.
#[no_mangle]
pub unsafe extern "C" fn diting_request_close(handle: *mut RuleSet) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle));
}

/// Drops a payload [`diting_request_match`] returned.
///
/// # Safety
///
/// `pointer` / `length` must be exactly what the call returned, and must not be freed twice.
#[no_mangle]
pub unsafe extern "C" fn diting_request_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

#[cfg(test)]
mod tests;
