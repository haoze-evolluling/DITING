//! The C ABI `android/engine/dns_core_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_dns_abi_version` | ABI number the loader validates |
//! | `diting_dns_query_info` | the logged name/type of one raw query |
//! | `diting_dns_validate` | one response checked against the query it answers |
//! | `diting_dns_extract` | everything the engine reads off one raw answer |
//! | `diting_dns_free_bytes` | drop a payload this library returned |
//! | `diting_dns_blocks_new` | the per-engine dynamic block tracker |
//! | `diting_dns_blocks_free` | drop a tracker and its state |
//! | `diting_dns_blocks_reset` | forget every domain counter (a new DNS config was applied) |
//! | `diting_dns_blocks_response` | the block response mode for one blocked query |
//! | `diting_dns_reply_block` | the configured block reply for one query (rcode + records) |
//! | `diting_dns_reply_local_asset` | the local asset host reply |
//! | `diting_dns_reply_ddr` | the DDR (RFC 9462) NXDOMAIN reply |
//! | `diting_dns_reply_servfail` | the SERVFAIL reply of the error paths |
//! | `diting_dns_reply_rewrite_ip` | the DNS-stage rewrite reply (A/AAAA) |
//! | `diting_dns_reply_rewrite_cname` | the CNAME redirect reply copied from a resolved answer |
//! | `diting_dns_rewrite_new` | build the per-domain rewrite table from the pushed rules |
//! | `diting_dns_rewrite_lookup` | the normalized rewrite entry for one domain (suffix walk) |
//! | `diting_dns_rewrite_free` | drop a rewrite table |
//!
//! Every duration and timestamp is nanoseconds and comes from Go; the kernel never reads a clock.
//! A null tracker echoes the fallback mode back, exactly like "dynamic response disabled".

use std::slice;

use crate::block::{BlockConfig, DynamicBlocks};
use crate::message::{extract, query_info, validate};
use crate::payload::{
    decode_rewrite_entries, encode_extracted, encode_lookup, encode_query_info, encode_reply,
    encode_validation,
};
use crate::reply;
use crate::rewrite_table::RewriteTable;

/// Must match `dnsCoreABIVersion` in `android/engine/dns_core_native.go`.
pub const ABI_VERSION: u32 = 3;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_dns_abi_version() -> u32 {
    ABI_VERSION
}

/// Reports the `parseDNSQuery` view of one raw query.
///
/// # Safety
///
/// `query` must be readable for `query_len` bytes and `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_query_info(
    query: *const u8,
    query_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() || (query.is_null() && query_len > 0) {
        return STATUS_BAD_ARGUMENT;
    }
    let data = if query_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(query, query_len)
    };
    let info = query_info(data);
    let encoded = encode_query_info(info.valid, &info.name, info.qtype);
    write_payload(encoded, out, out_len);
    STATUS_OK
}

/// Validates one raw response against one raw query.
///
/// # Safety
///
/// Both slices must be readable for their lengths and `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_validate(
    query: *const u8,
    query_len: usize,
    response: *const u8,
    response_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null()
        || out_len.is_null()
        || (query.is_null() && query_len > 0)
        || (response.is_null() && response_len > 0)
    {
        return STATUS_BAD_ARGUMENT;
    }
    let query = if query_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(query, query_len)
    };
    let response = if response_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(response, response_len)
    };
    let validation = validate(query, response);
    write_payload(
        encode_validation(validation.status, validation.rcode),
        out,
        out_len,
    );
    STATUS_OK
}

/// Extracts the engine-facing view of one raw answer. An unparsable answer is
/// [`STATUS_BAD_PAYLOAD`], not a semi-filled report.
///
/// # Safety
///
/// `response` must be readable for `response_len` bytes and `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_extract(
    response: *const u8,
    response_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() || (response.is_null() && response_len > 0) {
        return STATUS_BAD_ARGUMENT;
    }
    let data = if response_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(response, response_len)
    };
    let Some(extracted) = extract(data) else {
        return STATUS_BAD_PAYLOAD;
    };
    write_payload(encode_extracted(&extracted), out, out_len);
    STATUS_OK
}

/// Hands a boxed payload to Go: the allocation's capacity is its length, so Go can free it with
/// that length through [`diting_dns_free_bytes`].
unsafe fn write_payload(encoded: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = encoded.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
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

/// Borrows a byte-slice argument.
unsafe fn bytes<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        return Some(&[]);
    }
    if pointer.is_null() {
        return None;
    }
    Some(slice::from_raw_parts(pointer, length))
}

/// Encodes a plan (or reports a bad query) into `out` / `out_len`.
unsafe fn write_plan(
    plan: Option<reply::ReplyPlan>,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(plan) = plan else {
        return STATUS_BAD_PAYLOAD;
    };
    write_payload(encode_reply(&plan), out, out_len);
    STATUS_OK
}

/// The configured block reply for one query.
///
/// # Safety
///
/// `query` must be readable for `query_len` bytes; `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_reply_block(
    query: *const u8,
    query_len: usize,
    mode: u32,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(query) = bytes(query, query_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    write_plan(reply::block(query, mode as u8), out, out_len)
}

/// The local asset host reply.
///
/// # Safety
///
/// `query` must be readable for `query_len` bytes; `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_reply_local_asset(
    query: *const u8,
    query_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(query) = bytes(query, query_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    write_plan(reply::local_asset(query), out, out_len)
}

/// The DDR (RFC 9462) reply.
///
/// # Safety
///
/// `query` must be readable for `query_len` bytes; `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_reply_ddr(
    query: *const u8,
    query_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(query) = bytes(query, query_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    write_plan(reply::ddr(query), out, out_len)
}

/// The SERVFAIL reply.
///
/// # Safety
///
/// `query` must be readable for `query_len` bytes; `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_reply_servfail(
    query: *const u8,
    query_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(query) = bytes(query, query_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    write_plan(reply::servfail(query), out, out_len)
}

/// The DNS-stage rewrite reply for one address.
///
/// # Safety
///
/// `query` / `ip` must be readable for their lengths; `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_reply_rewrite_ip(
    query: *const u8,
    query_len: usize,
    ip: *const u8,
    ip_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let (Some(query), Some(ip)) = (bytes(query, query_len), text(ip, ip_len)) else {
        return STATUS_BAD_ARGUMENT;
    };
    write_plan(reply::rewrite_ip(query, ip), out, out_len)
}

/// The CNAME redirect reply, copying the matching A/AAAA records of `resolved`.
///
/// # Safety
///
/// `query` / `target` / `resolved` must be readable for their lengths; `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_reply_rewrite_cname(
    query: *const u8,
    query_len: usize,
    target: *const u8,
    target_len: usize,
    resolved: *const u8,
    resolved_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let (Some(query), Some(target), Some(resolved)) = (
        bytes(query, query_len),
        text(target, target_len),
        bytes(resolved, resolved_len),
    ) else {
        return STATUS_BAD_ARGUMENT;
    };
    write_plan(reply::rewrite_cname(query, target, resolved), out, out_len)
}

/// Builds a rewrite table from the `(domain, targets)` payload Go sends.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_rewrite_new(
    payload: *const u8,
    payload_len: usize,
) -> *mut RewriteTable {
    let Some(payload) = bytes(payload, payload_len) else {
        return std::ptr::null_mut();
    };
    let Some(entries) = decode_rewrite_entries(payload) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(RewriteTable::build(&entries)))
}

/// Looks up one domain in a rewrite table.
///
/// A missing entry is still a successful call (`found = 0`); a null handle is `STATUS_BAD_ARGUMENT`.
///
/// # Safety
///
/// The handle must be valid for the call; `domain` must be readable for `domain_len` bytes;
/// `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_rewrite_lookup(
    handle: *const RewriteTable,
    domain: *const u8,
    domain_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let (Some(table), Some(domain)) = (handle.as_ref(), text(domain, domain_len)) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    write_payload(encode_lookup(table.lookup(domain)), out, out_len);
    STATUS_OK
}

/// Drops a rewrite table created by [`diting_dns_rewrite_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_dns_rewrite_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_rewrite_free(handle: *mut RewriteTable) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[cfg(test)]
mod tests;
