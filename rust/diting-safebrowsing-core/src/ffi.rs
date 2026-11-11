//! The C ABI `desktop/service/internal/core/safebrowsing_native.go` loads with pure Go dlopen.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_sb_abi_version` | ABI number the loader validates |
//! | `diting_sb_new` | build a handle with the configured cache size / TTL |
//! | `diting_sb_free` | drop a handle and its caches |
//! | `diting_sb_free_bytes` | drop a payload this library returned |
//! | `diting_sb_configure` | apply a new size / TTL (rebuilds when either changed) |
//! | `diting_sb_plan` | normalize the host and report what one service still needs |
//! | `diting_sb_apply` | store one service's answer and report whether it blocks |
//!
//! A null handle makes every call a no-op (`plan` reports "skip", `apply` reports "not blocked"),
//! exactly like the other kernels.
//!
//! `plan` returns `0` when the host yields no verdict (empty, or not a domain name) and `1` with a
//! [`crate::payload`] plan otherwise. `apply` returns `0` for "does not block", `1` for "blocks"
//! and `2` for an undecodable request, which the Go side logs and treats as "does not block":
//! fail-open is the module's chosen direction for anything it cannot decide.

use std::slice;

use crate::engine::Engine;
use crate::hash::parse_txt_hashes;
use crate::payload::{decode_apply, encode_plan};

/// Must match `sbNativeABIVersion` in `desktop/service/internal/core/safebrowsing_native.go`.
pub const ABI_VERSION: u32 = 1;

/// `diting_sb_plan`: no verdict for this host.
pub const PLAN_SKIP: u32 = 0;
/// `diting_sb_plan`: a plan payload is available.
pub const PLAN_OK: u32 = 1;
/// `diting_sb_apply`: the digests do not block.
pub const APPLY_PASS: u32 = 0;
/// `diting_sb_apply`: the digests block.
pub const APPLY_BLOCK: u32 = 1;
/// `diting_sb_apply`: the request payload could not be decoded.
pub const APPLY_BAD_REQUEST: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_sb_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates a handle with the configured cache size (entries) and TTL (milliseconds), writing it to
/// `out`. Returns `1` on success and `0` when `out` is null.
///
/// Non-positive values fall back to the defaults, like `newHashCache` did.
///
/// # Safety
///
/// `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_sb_new(
    cache_size: i64,
    cache_ttl_ms: i64,
    out: *mut *mut Engine,
) -> u32 {
    if out.is_null() {
        return 0;
    }
    *out = Box::into_raw(Box::new(Engine::new(cache_size, cache_ttl_ms)));
    1
}

/// Drops a handle created by [`diting_sb_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_sb_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_sb_free(handle: *mut Engine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Frees a payload returned by this library.
///
/// # Safety
///
/// `pointer`/`length` must be a pair this library produced and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_sb_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Applies a new cache size (entries) and TTL (milliseconds).
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_sb_configure(
    handle: *const Engine,
    cache_size: i64,
    cache_ttl_ms: i64,
) {
    if let Some(engine) = handle.as_ref() {
        engine.configure(cache_size, cache_ttl_ms);
    }
}

/// Normalizes `host` and reports what `service` still needs, writing the plan payload to
/// `out_ptr`/`out_len`.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes and `out_ptr`/`out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_sb_plan(
    handle: *const Engine,
    service: u32,
    host: *const u8,
    host_len: usize,
    now_ms: i64,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if !out_ptr.is_null() {
        *out_ptr = std::ptr::null_mut();
    }
    if !out_len.is_null() {
        *out_len = 0;
    }
    let Some(engine) = handle.as_ref() else {
        return PLAN_SKIP;
    };
    let Some(host) = text(host, host_len) else {
        return PLAN_SKIP;
    };
    let Ok(service) = u8::try_from(service) else {
        return PLAN_SKIP;
    };
    let Some(plan) = engine.plan(service, host, now_ms) else {
        return PLAN_SKIP;
    };

    let payload = encode_plan(&plan);
    let length = payload.len();
    let boxed = payload.into_boxed_slice();
    if !out_ptr.is_null() {
        *out_ptr = Box::into_raw(boxed) as *mut u8;
    }
    if !out_len.is_null() {
        *out_len = length;
    }
    PLAN_OK
}

/// Stores one service's answer and reports whether it blocks.
///
/// # Safety
///
/// `request` must be readable for `request_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_sb_apply(
    handle: *const Engine,
    request: *const u8,
    request_len: usize,
    now_ms: i64,
) -> u32 {
    let Some(engine) = handle.as_ref() else {
        return APPLY_PASS;
    };
    let Some(request) = slice_from(request, request_len) else {
        return APPLY_BAD_REQUEST;
    };
    let Ok(decoded) = decode_apply(request) else {
        return APPLY_BAD_REQUEST;
    };
    let received = parse_txt_hashes(&decoded.received);
    if engine.apply(decoded.service, &decoded.queried, &received, now_ms) {
        APPLY_BLOCK
    } else {
        APPLY_PASS
    }
}

/// Reads a UTF-8 text argument; `None` when it is not valid UTF-8.
unsafe fn text<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    let bytes = slice_from(pointer, length)?;
    std::str::from_utf8(bytes).ok()
}

unsafe fn slice_from<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        return Some(&[]);
    }
    if pointer.is_null() {
        return None;
    }
    Some(slice::from_raw_parts(pointer, length))
}

#[cfg(test)]
mod tests;
