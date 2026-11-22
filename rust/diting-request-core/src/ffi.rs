use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;

use crate::payload::{build_rules, decode_match, decode_rules, encode_match};
use crate::rules::Rule;

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;
const STATUS_PANIC: u32 = 3;

pub struct RuleSet {
    rules: Vec<Rule>,
}

#[no_mangle]
pub extern "C" fn diting_request_abi_version() -> u32 {
    ABI_VERSION
}

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
    let mut boxed = encoded.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_request_close(handle: *mut RuleSet) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle));
}

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
