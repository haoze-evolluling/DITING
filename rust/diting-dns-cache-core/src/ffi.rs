use std::slice;

use crate::cache::Cache;
use crate::payload::{decode_config, encode_hit, encode_snapshot, encode_stats};
use crate::wire;

pub const ABI_VERSION: u32 = 3;

const STATUS_OK: u32 = 0;
const STATUS_REJECTED: u32 = 1;
const STATUS_BAD_ARGS: u32 = 2;

const LENGTH_INVALID: isize = -1;
const LENGTH_TOO_SMALL: isize = -2;

const GET_MISS: u32 = 0;
const GET_FRESH: u32 = 1;
const GET_STALE: u32 = 2;
const GET_BAD_ARGS: u32 = 3;

#[no_mangle]
pub extern "C" fn diting_dns_cache_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_question_key(
    wire: *const u8,
    wire_len: usize,
    out: *mut u8,
    out_cap: usize,
    name_len_out: *mut u32,
    qtype_out: *mut u16,
    qclass_out: *mut u16,
) -> isize {
    if out.is_null() || out_cap == 0 {
        return LENGTH_INVALID;
    }
    if name_len_out.is_null() || qtype_out.is_null() || qclass_out.is_null() {
        return LENGTH_INVALID;
    }
    let Some(data) = input(wire, wire_len) else {
        return LENGTH_INVALID;
    };
    let mut scratch = [0u8; wire::MAX_KEY_LEN];
    let Some(parts) = wire::write_question_key(data, &mut scratch) else {
        return LENGTH_INVALID;
    };
    if parts.key_len > out_cap {
        return LENGTH_TOO_SMALL;
    }
    std::ptr::copy_nonoverlapping(scratch.as_ptr(), out, parts.key_len);
    *name_len_out = parts.name_len as u32;
    *qtype_out = parts.qtype;
    *qclass_out = parts.qclass;
    parts.key_len as isize
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_new(
    config: *const u8,
    config_len: usize,
    flags_out: *mut u8,
    message_out: *mut *mut u8,
    message_len: *mut usize,
) -> *mut Cache {
    if flags_out.is_null() || message_out.is_null() || message_len.is_null() {
        return std::ptr::null_mut();
    }
    let Some(data) = input(config, config_len) else {
        write_payload(
            message("config pointer is null".to_string()),
            message_out,
            message_len,
        );
        return std::ptr::null_mut();
    };
    let normalized = match decode_config(data) {
        Ok(config) => config.normalized(),
        Err(error) => {
            write_payload(message(error), message_out, message_len);
            return std::ptr::null_mut();
        }
    };
    *flags_out = normalized.flags();
    write_payload(Vec::new(), message_out, message_len);
    let cache = Cache::new(normalized);
    std::sync::Arc::into_raw(cache) as *mut Cache
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_free(handle: *mut Cache) {
    if handle.is_null() {
        return;
    }
    drop(std::sync::Arc::from_raw(handle as *const Cache));
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_close(handle: *mut Cache) {
    if let Some(cache) = handle.as_ref() {
        cache.close();
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_update_policy(
    handle: *mut Cache,
    config: *const u8,
    config_len: usize,
    flags_out: *mut u8,
    message_out: *mut *mut u8,
    message_len: *mut usize,
) -> u32 {
    let Some(cache) = handle.as_ref() else {
        return STATUS_BAD_ARGS;
    };
    if flags_out.is_null() || message_out.is_null() || message_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    let Some(data) = input(config, config_len) else {
        write_payload(
            message("config pointer is null".to_string()),
            message_out,
            message_len,
        );
        return STATUS_BAD_ARGS;
    };
    match decode_config(data) {
        Ok(config) => {
            let config = config.normalized();
            *flags_out = config.flags();
            write_payload(Vec::new(), message_out, message_len);
            cache.update_policy(config);
            STATUS_OK
        }
        Err(error) => {
            write_payload(message(error), message_out, message_len);
            STATUS_REJECTED
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_clear(handle: *mut Cache) {
    if let Some(cache) = handle.as_ref() {
        cache.clear();
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_get(
    handle: *mut Cache,
    query: *const u8,
    query_len: usize,
    count: u8,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    let Some(cache) = handle.as_ref() else {
        return GET_BAD_ARGS;
    };
    if payload_out.is_null() || payload_len.is_null() {
        return GET_BAD_ARGS;
    }
    let Some(data) = input(query, query_len) else {
        return GET_BAD_ARGS;
    };
    match cache.get(data, count != 0) {
        Some(hit) => {
            let status = if hit.stale { GET_STALE } else { GET_FRESH };
            write_payload(encode_hit(&hit), payload_out, payload_len);
            status
        }
        None => {
            write_payload(Vec::new(), payload_out, payload_len);
            GET_MISS
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_put(
    handle: *mut Cache,
    query: *const u8,
    query_len: usize,
    response: *const u8,
    response_len: usize,
) -> u8 {
    let Some(cache) = handle.as_ref() else {
        return 0;
    };
    let (Some(query), Some(response)) = (input(query, query_len), input(response, response_len))
    else {
        return 0;
    };
    u8::from(cache.put(query, response))
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_refresh_begin(
    handle: *mut Cache,
    query: *const u8,
    query_len: usize,
) -> u8 {
    let Some(cache) = handle.as_ref() else {
        return 0;
    };
    match input(query, query_len) {
        Some(data) => u8::from(cache.refresh_begin(data)),
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_refresh_done(
    handle: *mut Cache,
    query: *const u8,
    query_len: usize,
) {
    let Some(cache) = handle.as_ref() else {
        return;
    };
    if let Some(data) = input(query, query_len) {
        cache.refresh_done(data);
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_stats(
    handle: *mut Cache,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) {
    if payload_out.is_null() || payload_len.is_null() {
        return;
    }
    let empty = crate::cache::Stats {
        enabled: false,
        total_hits: 0,
        total_misses: 0,
        stale_hits: 0,
        negative_hits: 0,
        evictions: 0,
        entry_count: 0,
        max_entries: 0,
    };
    let stats = match handle.as_ref() {
        Some(cache) => cache.stats(),
        None => empty,
    };
    write_payload(encode_stats(&stats), payload_out, payload_len);
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_snapshot(
    handle: *mut Cache,
    limit: u32,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) {
    if payload_out.is_null() || payload_len.is_null() {
        return;
    }
    let entries = match handle.as_ref() {
        Some(cache) => cache.snapshot(limit),
        None => Vec::new(),
    };
    write_payload(encode_snapshot(&entries), payload_out, payload_len);
}

#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

unsafe fn input<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        Some(&[])
    } else if pointer.is_null() {
        None
    } else {
        Some(slice::from_raw_parts(pointer, length))
    }
}

fn message(text: String) -> Vec<u8> {
    text.into_bytes()
}

unsafe fn write_payload(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = bytes.into_boxed_slice();
    *out_len = boxed.len();
    *out = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

#[cfg(test)]
pub(crate) fn encode_test_config(config: &crate::policy::Config, mode: &str) -> Vec<u8> {
    use crate::policy::{FLAG_ENABLED, FLAG_MIN_TTL, FLAG_NEGATIVE_TTL, FLAG_STALE_FALLBACK};
    let mut flags = 0u8;
    if config.enabled {
        flags |= FLAG_ENABLED;
    }
    if config.min_ttl_enabled {
        flags |= FLAG_MIN_TTL;
    }
    if config.stale_fallback_enabled {
        flags |= FLAG_STALE_FALLBACK;
    }
    if config.negative_ttl_enabled {
        flags |= FLAG_NEGATIVE_TTL;
    }
    let mut out = vec![crate::payload::LAYOUT_VERSION, flags];
    for value in [
        config.max_ttl_seconds,
        config.fixed_ttl_seconds,
        config.min_ttl_seconds,
        config.stale_fallback_seconds,
        config.negative_ttl_seconds,
        config.ttl_scale_percent,
    ] {
        out.extend_from_slice(&value.to_le_bytes());
    }
    out.extend_from_slice(&(mode.len() as u32).to_le_bytes());
    out.extend_from_slice(mode.as_bytes());
    out
}

#[cfg(test)]
mod tests;
