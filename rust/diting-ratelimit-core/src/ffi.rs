//! The C ABI `desktop/service/internal/core/ratelimit_native.go` loads with pure Go dlopen.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_ratelimit_abi_version` | ABI number the loader validates |
//! | `diting_ratelimit_new` | one limiter from an encoded config |
//! | `diting_ratelimit_configure` | replace config + exemptions, keep the buckets |
//! | `diting_ratelimit_free` | drop a limiter |
//! | `diting_ratelimit_free_bytes` | drop a payload this library returned |
//! | `diting_ratelimit_allow` | one decision: `1` allow, `0` deny, `-1` unusable argument |
//! | `diting_ratelimit_cleanup` | the janitor's idle sweep |
//! | `diting_ratelimit_info` | normalised config + table sizes |
//!
//! A null handle allows every request (the "protection unavailable" shape) and ignores cleanup;
//! `info` on a null handle fails. The Go side never builds one: a missing library fails
//! `NewRateLimiter`.
//!
//! `addr_len == 0` is a `nil` `net.IP`, which the original `Allow` passed through without touching
//! a bucket. Any other length than 4 or 16 is a caller bug and reported as `-1`; the Go wrapper
//! treats that like "no decision" and allows, so a broken address can never lock a client out.

use std::slice;

use crate::ip::Addr;
use crate::limiter::RateLimiter;
use crate::payload::{decode_config, encode_info};

/// Must match `rateLimitNativeABIVersion` in `desktop/service/internal/core/ratelimit_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 1;
const STATUS_BAD_ARGUMENT: u32 = 0;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_ratelimit_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates a limiter; writes the handle to `out`.
///
/// # Safety
///
/// `config` must be readable for `config_len` bytes and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_new(
    config: *const u8,
    config_len: usize,
    out: *mut *mut RateLimiter,
) -> u32 {
    if out.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    *out = std::ptr::null_mut();
    let Some(data) = slice_from(config, config_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    let Ok(decoded) = decode_config(data) else {
        return STATUS_BAD_ARGUMENT;
    };
    *out = Box::into_raw(Box::new(RateLimiter::new(&decoded)));
    STATUS_OK
}

/// Applies a new configuration to a live limiter.
///
/// # Safety
///
/// `handle` must come from [`diting_ratelimit_new`] and `config` must be readable for
/// `config_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_configure(
    handle: *const RateLimiter,
    config: *const u8,
    config_len: usize,
) -> u32 {
    let Some(limiter) = handle.as_ref() else {
        return STATUS_BAD_ARGUMENT;
    };
    let Some(data) = slice_from(config, config_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    let Ok(decoded) = decode_config(data) else {
        return STATUS_BAD_ARGUMENT;
    };
    limiter.configure(&decoded);
    STATUS_OK
}

/// Drops a limiter created by [`diting_ratelimit_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_ratelimit_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_free(handle: *mut RateLimiter) {
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
pub unsafe extern "C" fn diting_ratelimit_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// `Allow`: `1` allow, `0` deny, `-1` unusable argument.
///
/// # Safety
///
/// `address` must be readable for `address_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_allow(
    handle: *const RateLimiter,
    address: *const u8,
    address_len: usize,
    now_ns: i64,
    max_buckets: u32,
) -> i32 {
    let Some(limiter) = handle.as_ref() else {
        return 1;
    };
    if address_len == 0 {
        return i32::from(limiter.allow(None, now_ns, max_buckets));
    }
    let Some(bytes) = slice_from(address, address_len) else {
        return -1;
    };
    let Some(address) = Addr::from_bytes(bytes) else {
        return -1;
    };
    i32::from(limiter.allow(Some(&address), now_ns, max_buckets))
}

/// The janitor's idle sweep.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_cleanup(handle: *const RateLimiter, now_ns: i64) {
    if let Some(limiter) = handle.as_ref() {
        limiter.cleanup_idle(now_ns);
    }
}

/// Writes the normalised config and the table sizes.
///
/// # Safety
///
/// `out_ptr`/`out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_info(
    handle: *const RateLimiter,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(limiter) = handle.as_ref() else {
        return STATUS_BAD_ARGUMENT;
    };
    write_payload(encode_info(&limiter.info()), out_ptr, out_len)
}

unsafe fn write_payload(payload: Vec<u8>, out_ptr: *mut *mut u8, out_len: *mut usize) -> u32 {
    if !out_ptr.is_null() {
        *out_ptr = std::ptr::null_mut();
    }
    if !out_len.is_null() {
        *out_len = 0;
    }
    let length = payload.len();
    let boxed = payload.into_boxed_slice();
    if !out_ptr.is_null() {
        *out_ptr = Box::into_raw(boxed) as *mut u8;
    }
    if !out_len.is_null() {
        *out_len = length;
    }
    STATUS_OK
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
