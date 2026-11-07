//! The C ABI `android/engine/ipcache_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_ipcache_abi_version` | ABI number the loader validates |
//! | `diting_ipcache_new` | one engine's cache with the requested capacity |
//! | `diting_ipcache_free` | drop a handle |
//! | `diting_ipcache_put` | remember (or refresh) one IP → domain mapping |
//! | `diting_ipcache_get` | copy the domain text into the caller's buffer |
//! | `diting_ipcache_len` | current entry count (tests) |
//!
//! A null handle misses every lookup and ignores writes, which is the "cache unavailable" shape.
//! Empty IPs/domains are no-ops on both sides.

use std::slice;
use std::str;

use crate::cache::IpDomainCache;

/// Must match `ipCacheABIVersion` in `android/engine/ipcache_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;

const RESULT_MISS: isize = -1;
const RESULT_TOO_SMALL: isize = -2;
const RESULT_BAD_ARGUMENT: isize = -3;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_ipcache_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates a cache; a non-positive capacity means the default 2048.
#[no_mangle]
pub extern "C" fn diting_ipcache_new(max_size: i32) -> *mut IpDomainCache {
    Box::into_raw(Box::new(IpDomainCache::new(max_size)))
}

/// Drops a handle created by [`diting_ipcache_new`].
///
/// # Safety
///
/// `handle` must come from `diting_ipcache_new` and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_ipcache_free(handle: *mut IpDomainCache) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// `put`: empty keys are ignored by the kernel; a null handle is a no-op.
///
/// # Safety
///
/// Both slices must be readable for their stated lengths.
#[no_mangle]
pub unsafe extern "C" fn diting_ipcache_put(
    handle: *const IpDomainCache,
    ip: *const u8,
    ip_len: usize,
    domain: *const u8,
    domain_len: usize,
) -> u32 {
    let Some(cache) = handle.as_ref() else {
        return STATUS_OK;
    };
    let (Some(ip), Some(domain)) = (text_argument(ip, ip_len), text_argument(domain, domain_len))
    else {
        return STATUS_BAD_ARGUMENT;
    };
    cache.put(ip, domain);
    STATUS_OK
}

/// `get`: writes the domain text and returns its length, or `-1` on a miss.
///
/// # Safety
///
/// `ip` must be readable for `ip_len` bytes and `out` writable for `out_cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_ipcache_get(
    handle: *const IpDomainCache,
    ip: *const u8,
    ip_len: usize,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let Some(cache) = handle.as_ref() else {
        return RESULT_MISS;
    };
    if out.is_null() {
        return RESULT_BAD_ARGUMENT;
    }
    let Some(ip) = text_argument(ip, ip_len) else {
        return RESULT_BAD_ARGUMENT;
    };
    if ip.is_empty() {
        return RESULT_MISS;
    }
    match cache.get(ip) {
        None => RESULT_MISS,
        Some(domain) => {
            if out_cap < domain.len() {
                return RESULT_TOO_SMALL;
            }
            std::ptr::copy_nonoverlapping(domain.as_ptr(), out, domain.len());
            domain.len() as isize
        }
    }
}

/// Current entry count.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_ipcache_len(handle: *const IpDomainCache) -> u32 {
    handle.as_ref().map_or(0, IpDomainCache::len)
}

/// Reads a text argument. A zero length is the empty string; a null pointer with a non-zero length
/// or invalid UTF-8 is a caller bug.
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
