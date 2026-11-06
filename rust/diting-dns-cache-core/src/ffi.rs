//! The C ABI `android/engine/dns_cache_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_dns_cache_abi_version` | ABI number the loader validates |
//! | `diting_dns_cache_question_key` | cache key of the first question, written into a caller buffer |
//! | `diting_dns_cache_parse_response` | metadata of one response as a [`crate::payload`] payload |
//! | `diting_dns_cache_patch_response` | copy of a response with the query ID and all TTLs replaced |
//! | `diting_dns_cache_free_bytes` | drop a payload this library returned |
//!
//! The hot paths take caller buffers (`question_key`, `patch_response`) so a cache hit allocates
//! exactly what the old Go code allocated: nothing for the key, one copy for the patched wire.
//! Nothing is cached between calls; Go owns the shards, the LRU and the TTL policy.

use std::slice;

use crate::payload::encode_response_meta;
use crate::wire;

/// Must match `dnsCacheABIVersion` in `android/engine/dns_cache_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_REJECTED: u32 = 1;
const STATUS_BAD_ARGS: u32 = 2;

/// Returned by [`diting_dns_cache_question_key`] / [`diting_dns_cache_patch_response`].
const LENGTH_INVALID: isize = -1;
const LENGTH_TOO_SMALL: isize = -2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_dns_cache_abi_version() -> u32 {
    ABI_VERSION
}

/// Builds the cache key of the first question and writes it into `out`.
///
/// Returns the key length, [`LENGTH_INVALID`] when the question cannot be read, or
/// [`LENGTH_TOO_SMALL`] when `out_cap` cannot hold the key (a cache key is at most
/// [`wire::MAX_KEY_LEN`] bytes). `name_len_out`, `qtype_out` and `qclass_out` receive the split
/// parts so Go never has to parse the key back.
///
/// # Safety
///
/// `wire` must be readable for `wire_len` bytes, `out` writable for `out_cap` bytes and the three
/// out pointers valid for writes.
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
    // Build in a stack buffer: the caller's buffer is sized by Go and a too-small one must be
    // reported (not truncated), so the key is built first and then copied out.
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

/// Parses one response into the [`crate::payload`] layout.
///
/// `STATUS_REJECTED` means the answer must not be cached; the payload is empty then. There is no
/// diagnostic message on purpose: a malformed upstream answer was silently skipped before, and the
/// cache write path must not log per response.
///
/// # Safety
///
/// `wire` must be readable for `wire_len` bytes; `payload_out`/`payload_len` must be valid for
/// writes.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_parse_response(
    wire: *const u8,
    wire_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    let Some(data) = input(wire, wire_len) else {
        return STATUS_BAD_ARGS;
    };
    match wire::parse_response(data) {
        Some(meta) => {
            write_payload(encode_response_meta(&meta), payload_out, payload_len);
            STATUS_OK
        }
        None => {
            write_payload(Vec::new(), payload_out, payload_len);
            STATUS_REJECTED
        }
    }
}

/// Copies `wire` into `out` and replaces the query ID and every indexed TTL.
///
/// Returns `wire_len` on success, [`LENGTH_INVALID`] when the wire or the offsets are unreadable,
/// and [`LENGTH_TOO_SMALL`] when `out_cap < wire_len`. Offsets past the end are ignored, exactly
/// like the Go patcher did.
///
/// # Safety
///
/// `wire` and `offsets` must be readable for their lengths; `out` must be writable for `out_cap`.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_patch_response(
    wire: *const u8,
    wire_len: usize,
    offsets: *const u16,
    offsets_len: usize,
    query_id: u16,
    ttl: u32,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    if out.is_null() || out_cap < wire_len {
        return LENGTH_TOO_SMALL;
    }
    if offsets.is_null() && offsets_len > 0 {
        return LENGTH_INVALID;
    }
    let Some(data) = input(wire, wire_len) else {
        return LENGTH_INVALID;
    };
    let offsets = if offsets_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(offsets, offsets_len)
    };
    let target = slice::from_raw_parts_mut(out, wire_len);
    if !wire::patch_response_into(data, offsets, query_id, ttl, target) {
        return LENGTH_INVALID;
    }
    wire_len as isize
}

/// Frees a payload returned by this library.
///
/// # Safety
///
/// `pointer`/`length` must be a pair this library produced and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_cache_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Rebuilds the input slice; a null pointer with a non-zero length is a caller bug.
unsafe fn input<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        Some(&[])
    } else if pointer.is_null() {
        None
    } else {
        Some(slice::from_raw_parts(pointer, length))
    }
}

/// Hands a `Vec<u8>` to the caller; the length travels with the pointer so Go can rebuild the same
/// allocation in [`diting_dns_cache_free_bytes`].
unsafe fn write_payload(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = bytes.into_boxed_slice();
    *out_len = boxed.len();
    *out = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

#[cfg(test)]
mod tests;
