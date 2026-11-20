use std::slice;
use std::str;

use crate::cache::IpDomainCache;

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;

const RESULT_MISS: isize = -1;
const RESULT_TOO_SMALL: isize = -2;
const RESULT_BAD_ARGUMENT: isize = -3;

#[no_mangle]
pub extern "C" fn diting_ipcache_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn diting_ipcache_new(max_size: i32) -> *mut IpDomainCache {
    Box::into_raw(Box::new(IpDomainCache::new(max_size)))
}

#[no_mangle]
pub unsafe extern "C" fn diting_ipcache_free(handle: *mut IpDomainCache) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_ipcache_len(handle: *const IpDomainCache) -> u32 {
    handle.as_ref().map_or(0, IpDomainCache::len)
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
