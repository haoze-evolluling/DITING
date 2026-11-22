use std::slice;

use crate::host::{link_tag, normalize_host};
use crate::inject::{Injector, Outcome, Upstream};
use crate::local::{is_asset_host, respond};
use crate::payload::{decode_rules, decode_text, encode_response, encode_text, encode_text_list};
use crate::rules::{host_suffixes, RuleSet};

pub const ABI_VERSION: u32 = 2;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

#[no_mangle]
pub extern "C" fn diting_cosmetic_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_link_tag(
    host: *const u8,
    host_len: usize,
    asset_host: *const u8,
    asset_host_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(host) = text(host, host_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    let Some(asset_host) = text(asset_host, asset_host_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    write_text(out, out_len, link_tag(&host, &asset_host).as_bytes())
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_normalize_host(
    host: *const u8,
    host_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(host) = text(host, host_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    write_text(out, out_len, normalize_host(&host).as_bytes())
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_rules_new(
    payload: *const u8,
    payload_len: usize,
    out: *mut *mut RuleSet,
) -> u32 {
    let Some(payload) = slice_from(payload, payload_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Ok(rules) = decode_rules(payload) else {
        return STATUS_BAD_PAYLOAD;
    };
    *out = Box::into_raw(Box::new(rules));
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_rules_free(handle: *mut RuleSet) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle));
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_rules_render(
    handle: *const RuleSet,
    host: *const u8,
    host_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(host) = text(host, host_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    match handle.as_ref() {
        Some(rules) => write_text(out, out_len, rules.render(&host).as_bytes()),
        None => write_text(out, out_len, RuleSet::Empty.render(&host).as_bytes()),
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_host_suffixes(
    host: *const u8,
    host_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(host) = text(host, host_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    write_payload(out, out_len, encode_text_list(&host_suffixes(&host)))
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_is_asset_host(host: *const u8, host_len: usize) -> i32 {
    let Some(host) = text(host, host_len) else {
        return 0;
    };
    i32::from(is_asset_host(&host))
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_local_response(
    handle: *const RuleSet,
    path: *const u8,
    path_len: usize,
    host_query: *const u8,
    host_query_len: usize,
    payload_bytes: u64,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let (Some(path), Some(host_query)) = (text(path, path_len), text(host_query, host_query_len))
    else {
        return STATUS_BAD_ARGUMENT;
    };
    let empty = RuleSet::Empty;
    let rules = handle.as_ref().unwrap_or(&empty);
    write_payload(
        out,
        out_len,
        encode_response(&respond(&path, &host_query, rules, payload_bytes)),
    )
}

unsafe fn write_payload(out: *mut *mut u8, out_len: *mut usize, encoded: Vec<u8>) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let mut payload = encoded.into_boxed_slice();
    let length = payload.len();
    let pointer = payload.as_mut_ptr();
    std::mem::forget(payload);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

fn write_text(out: *mut *mut u8, out_len: *mut usize, text: &[u8]) -> u32 {
    let mut payload = encode_text(text).into_boxed_slice();
    let length = payload.len();
    let pointer = payload.as_mut_ptr();
    std::mem::forget(payload);
    unsafe {
        *out = pointer;
        *out_len = length;
    }
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, length, length));
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_new(
    link: *const u8,
    link_len: usize,
    out: *mut *mut Injector,
) -> u32 {
    let Some(link) = slice_from(link, link_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let tag = match decode_text(link) {
        Ok(tag) => tag,
        Err(_) => return STATUS_BAD_PAYLOAD,
    };
    *out = Box::into_raw(Box::new(Injector::new(tag.into_bytes())));
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_free(handle: *mut Injector) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle));
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_pending(
    handle: *mut Injector,
    buffer: *mut u8,
    capacity: usize,
) -> u32 {
    let Some(injector) = handle.as_mut() else {
        return 0;
    };
    let Some(buffer) = buffer_range(buffer, capacity) else {
        return 0;
    };
    injector.pending_into(buffer) as u32
}

#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_process(
    handle: *mut Injector,
    buffer: *mut u8,
    capacity: usize,
    n: usize,
    flags: u32,
    out_len: *mut u32,
    out_keep_error: *mut u8,
) -> u32 {
    let Some(injector) = handle.as_mut() else {
        return STATUS_BAD_ARGUMENT;
    };
    let Some(buffer) = buffer_range(buffer, capacity) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out_len.is_null() || out_keep_error.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Outcome {
        out_len: written,
        keep_error,
    } = injector.process(buffer, n, Upstream::from_abi(flags));
    *out_len = written as u32;
    *out_keep_error = u8::from(keep_error);
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

unsafe fn buffer_range<'a>(pointer: *mut u8, capacity: usize) -> Option<&'a mut [u8]> {
    if capacity == 0 {
        return Some(&mut []);
    }
    if pointer.is_null() {
        return None;
    }
    Some(slice::from_raw_parts_mut(pointer, capacity))
}

unsafe fn text(pointer: *const u8, length: usize) -> Option<String> {
    let bytes = slice_from(pointer, length)?;
    Some(String::from_utf8_lossy(bytes).into_owned())
}

#[cfg(test)]
mod tests;
