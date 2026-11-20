use std::slice;

use crate::engine::Engine;
use crate::hash::parse_txt_hashes;
use crate::payload::{decode_apply, encode_plan};

pub const ABI_VERSION: u32 = 1;

pub const PLAN_SKIP: u32 = 0;
pub const PLAN_OK: u32 = 1;
pub const APPLY_PASS: u32 = 0;
pub const APPLY_BLOCK: u32 = 1;
pub const APPLY_BAD_REQUEST: u32 = 2;

#[no_mangle]
pub extern "C" fn diting_sb_abi_version() -> u32 {
    ABI_VERSION
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_sb_free(handle: *mut Engine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_sb_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

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
