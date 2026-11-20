use std::slice;

use crate::engine::Engine;
use crate::payload::{decode_addresses, decode_prefixes, encode_result};
use crate::prefix::{Prefix, DNS64_PREFIX_LENGTHS};

pub const ABI_VERSION: u32 = 1;

const STATUS_PREFIX_PARSE: u32 = 3;
const STATUS_PREFIX_LENGTH: u32 = 4;

#[no_mangle]
pub extern "C" fn diting_dns64_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_new(
    enabled: u8,
    prefixes: *const u8,
    prefixes_len: usize,
    out: *mut *mut Engine,
    out_index: *mut u32,
) -> u32 {
    if out.is_null() {
        return 1;
    }
    let Some(data) = slice_from(prefixes, prefixes_len) else {
        return 1;
    };
    let Ok(decoded) = decode_prefixes(data) else {
        return 2;
    };
    match Engine::new(enabled != 0, &decoded) {
        Ok(engine) => {
            *out = Box::into_raw(Box::new(engine));
            0
        }
        Err(rejection) => {
            if !out_index.is_null() {
                *out_index = rejection.index as u32;
            }
            match rejection.error {
                crate::prefix::PrefixError::Parse => STATUS_PREFIX_PARSE,
                crate::prefix::PrefixError::Length => STATUS_PREFIX_LENGTH,
            }
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_free(handle: *mut Engine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_info(
    handle: *const Engine,
    out_enabled: *mut u8,
    out_prefixes: *mut u32,
) -> u32 {
    let Some(engine) = handle.as_ref() else {
        return 1;
    };
    if !out_enabled.is_null() {
        *out_enabled = u8::from(engine.is_enabled());
    }
    if !out_prefixes.is_null() {
        *out_prefixes = engine.prefix_count() as u32;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_embed(
    handle: *const Engine,
    v4: *const u8,
    v4_len: usize,
    out: *mut u8,
) -> u32 {
    let Some(engine) = handle.as_ref() else {
        return 1;
    };
    let Some(v4) = v4_address(v4, v4_len) else {
        return 1;
    };
    write_bytes(out, &engine.map(v4))
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_embed_net(
    prefix: *const u8,
    ones: u8,
    v4: *const u8,
    v4_len: usize,
    out: *mut u8,
) -> u32 {
    let Some(prefix) = slice_from(prefix, 16) else {
        return 1;
    };
    let Ok(addr) = <[u8; 16]>::try_from(prefix) else {
        return 1;
    };
    let Some(v4) = v4_address(v4, v4_len) else {
        return 1;
    };
    let candidate = Prefix { addr, ones };
    if !DNS64_PREFIX_LENGTHS.contains(&ones) {
        return STATUS_PREFIX_LENGTH;
    }
    write_bytes(out, &candidate.embed(v4))
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_synthesize(
    handle: *const Engine,
    v4: *const u8,
    v4_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(engine) = handle.as_ref() else {
        return 1;
    };
    let address = if v4_len == 0 {
        None
    } else {
        match v4_address(v4, v4_len) {
            Some(v4) => Some(v4),
            None => return 1,
        }
    };
    write_payload(encode_result(&engine.synthesize(address)), out_ptr, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_excluded(
    handle: *const Engine,
    address: *const u8,
    address_len: usize,
    out: *mut u8,
) -> u32 {
    let Some(engine) = handle.as_ref() else {
        return 1;
    };
    let Some(bytes) = slice_from(address, address_len) else {
        return 1;
    };
    if out.is_null() {
        return 1;
    }
    *out = u8::from(engine.excluded(bytes));
    0
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns64_has_valid(
    handle: *const Engine,
    data: *const u8,
    data_len: usize,
    out: *mut u8,
) -> u32 {
    let Some(engine) = handle.as_ref() else {
        return 1;
    };
    let Some(payload) = slice_from(data, data_len) else {
        return 1;
    };
    let Ok(addresses) = decode_addresses(payload) else {
        return 2;
    };
    if out.is_null() {
        return 1;
    }
    let borrowed: Vec<&[u8]> = addresses.iter().map(Vec::as_slice).collect();
    *out = u8::from(engine.has_valid_aaaa(&borrowed));
    0
}

unsafe fn write_bytes(out: *mut u8, bytes: &[u8]) -> u32 {
    if out.is_null() {
        return 1;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len());
    0
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
    0
}

unsafe fn v4_address(pointer: *const u8, length: usize) -> Option<[u8; 4]> {
    let bytes = slice_from(pointer, length)?;
    <[u8; 4]>::try_from(bytes).ok()
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
