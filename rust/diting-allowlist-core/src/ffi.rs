use std::slice;
use std::str;

use crate::engine::AllowlistKernel;
use crate::payload::{decode_configure, decode_remember};

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

#[no_mangle]
pub extern "C" fn diting_allowlist_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn diting_allowlist_new() -> *mut AllowlistKernel {
    Box::into_raw(Box::new(AllowlistKernel::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_free(handle: *mut AllowlistKernel) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_configure(
    handle: *const AllowlistKernel,
    payload: *const u8,
    payload_len: usize,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return STATUS_OK;
    };
    if payload.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(entries) = decode_configure(slice::from_raw_parts(payload, payload_len)) else {
        return STATUS_BAD_PAYLOAD;
    };
    kernel.configure(&entries);
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_has_uids(handle: *const AllowlistKernel) -> u32 {
    match handle.as_ref() {
        Some(kernel) => u32::from(kernel.has_uids()),
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_domain_allowed(
    handle: *const AllowlistKernel,
    uid: i32,
    domain: *const u8,
    domain_len: usize,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return 1;
    };
    let Some(domain) = text_argument(domain, domain_len) else {
        return 0;
    };
    u32::from(kernel.domain_allowed(uid, domain))
}

#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_connection_allowed(
    handle: *const AllowlistKernel,
    uid: i32,
    address: *const u8,
    address_len: usize,
    now_ns: i64,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return 1;
    };
    let address = if address_len == 0 {
        &[][..]
    } else if address.is_null() {
        return 0;
    } else {
        slice::from_raw_parts(address, address_len)
    };
    u32::from(kernel.connection_allowed(uid, address, now_ns))
}

#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_remember(
    handle: *const AllowlistKernel,
    payload: *const u8,
    payload_len: usize,
    now_ns: i64,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return STATUS_OK;
    };
    if payload.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(request) = decode_remember(slice::from_raw_parts(payload, payload_len)) else {
        return STATUS_BAD_PAYLOAD;
    };
    kernel.remember(
        request.uid,
        &request.question_name,
        &request.records,
        now_ns,
    );
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_grant_count(
    handle: *const AllowlistKernel,
    uid: i32,
) -> u32 {
    match handle.as_ref() {
        Some(kernel) => kernel.grant_count(uid),
        None => 0,
    }
}

unsafe fn text_argument<'a>(text: *const u8, len: usize) -> Option<&'a str> {
    if len == 0 {
        return Some("");
    }
    if text.is_null() {
        return None;
    }
    str::from_utf8(slice::from_raw_parts(text, len)).ok()
}

#[cfg(test)]
mod tests;
