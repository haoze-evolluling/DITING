//! The C ABI `android/engine/dns_core_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_dns_abi_version` | ABI number the loader validates |
//! | `diting_dns_inspect_answer` | null-block verdict + unique address text for one answer |
//! | `diting_dns_free_bytes` | drop a payload this library returned |
//! | `diting_dns_blocks_new` | the per-engine dynamic block tracker |
//! | `diting_dns_blocks_free` | drop a tracker and its state |
//! | `diting_dns_blocks_reset` | forget every domain counter (a new DNS config was applied) |
//! | `diting_dns_blocks_response` | the block response mode for one blocked query |
//!
//! Every duration and timestamp is nanoseconds and comes from Go; the kernel never reads a clock.
//! A null tracker echoes the fallback mode back, exactly like "dynamic response disabled".

use std::slice;

use crate::answer::inspect;
use crate::block::{BlockConfig, DynamicBlocks};
use crate::payload::{decode_answer_request, encode_answer_response};

/// Must match `dnsCoreABIVersion` in `android/engine/dns_core_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_dns_abi_version() -> u32 {
    ABI_VERSION
}

/// Inspects one answer and writes the encoded result to `out` / `out_len`.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes and `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_inspect_answer(
    payload: *const u8,
    payload_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if payload.is_null() || out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(entries) = decode_answer_request(slice::from_raw_parts(payload, payload_len)) else {
        return STATUS_BAD_PAYLOAD;
    };
    let inspection = inspect(&entries);
    let encoded = encode_answer_response(inspection.blocked, &inspection.addresses);
    // A boxed slice so the allocation's capacity is its length: Go frees it with that length.
    let mut boxed = encoded.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

/// Frees a payload returned by this library.
///
/// # Safety
///
/// `pointer`/`length` must be a pair this library produced and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Creates the dynamic block tracker of one engine.
#[no_mangle]
pub extern "C" fn diting_dns_blocks_new() -> *mut DynamicBlocks {
    Box::into_raw(Box::new(DynamicBlocks::new()))
}

/// Drops a tracker created by [`diting_dns_blocks_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_dns_blocks_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_blocks_free(handle: *mut DynamicBlocks) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Forgets every per-domain counter.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_blocks_reset(handle: *const DynamicBlocks) {
    if let Some(blocks) = handle.as_ref() {
        blocks.reset();
    }
}

/// Resolves the block response mode for one blocked query.
///
/// `domain` is already normalized by Go (trimmed, lowercased, no trailing dot). A handle that
/// cannot be read, a non-UTF-8 domain or a null handle all echo `fallback` back.
///
/// # Safety
///
/// `domain` must be readable for `domain_len` bytes; the handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_blocks_response(
    handle: *const DynamicBlocks,
    domain: *const u8,
    domain_len: usize,
    enabled: u32,
    threshold: u32,
    window_ns: i64,
    nxdomain_ns: i64,
    fallback: u32,
    now_ns: i64,
) -> u32 {
    let (Some(blocks), Some(domain)) = (handle.as_ref(), text(domain, domain_len)) else {
        return fallback;
    };
    blocks.response_for(
        domain,
        &BlockConfig {
            enabled: enabled != 0,
            request_threshold: threshold,
            window_ns,
            nx_domain_ns: nxdomain_ns,
        },
        fallback,
        now_ns,
    )
}

/// Borrows a UTF-8 text argument. Go hands these into a call and never keeps the pointer.
unsafe fn text<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    if length == 0 {
        return Some("");
    }
    if pointer.is_null() {
        return None;
    }
    std::str::from_utf8(slice::from_raw_parts(pointer, length)).ok()
}

#[cfg(test)]
mod tests;
