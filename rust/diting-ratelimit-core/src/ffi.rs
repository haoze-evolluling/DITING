use std::slice;

use crate::ip::Addr;
use crate::limiter::RateLimiter;
use crate::payload::{decode_config, encode_info};

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 1;
const STATUS_BAD_ARGUMENT: u32 = 0;

#[no_mangle]
pub extern "C" fn diting_ratelimit_abi_version() -> u32 {
    ABI_VERSION
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_free(handle: *mut RateLimiter) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_ratelimit_cleanup(handle: *const RateLimiter, now_ns: i64) {
    if let Some(limiter) = handle.as_ref() {
        limiter.cleanup_idle(now_ns);
    }
}

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
