//! The C ABI `desktop/service/internal/core/dns64_native.go` loads with pure Go dlopen.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_dns64_abi_version` | ABI number the loader validates |
//! | `diting_dns64_new` | build a synthesizer from the configured prefixes |
//! | `diting_dns64_free` | drop one |
//! | `diting_dns64_free_bytes` | drop a payload this library returned |
//! | `diting_dns64_info` | enabled flag + configured prefix count |
//! | `diting_dns64_embed` | `MapIPv4ToIPv6`: embed behind the first prefix |
//! | `diting_dns64_embed_net` | `EmbedIPv4InIPv6`: embed behind a 16-byte prefix + length |
//! | `diting_dns64_synthesize` | the AAAA addresses for one A record |
//! | `diting_dns64_excluded` | `IsExcluded` |
//! | `diting_dns64_has_valid` | `HasValidAAAARecords` over extracted addresses |
//!
//! Status codes, shared by every function:
//!
//! * `0` — ok
//! * `1` — bad argument (null handle or pointer, or an address that is not 4 bytes wide)
//! * `2` — the payload did not decode
//! * `3` — the prefix text is not a CIDR (`net.ParseCIDR` would fail)
//! * `4` — the prefix parsed but is not an RFC 6052 length (this includes every IPv4 CIDR)
//!
//! `diting_dns64_new` also writes the index of the offending prefix, so Go can quote the entry the
//! user typed instead of the text after trimming. The error *wording* stays in Go: it is the text
//! the old constructor produced.

use std::slice;

use crate::engine::Engine;
use crate::payload::{decode_addresses, decode_prefixes, encode_result};
use crate::prefix::{Prefix, DNS64_PREFIX_LENGTHS};

/// Must match `dns64NativeABIVersion` in `desktop/service/internal/core/dns64_native.go`.
pub const ABI_VERSION: u32 = 1;

/// A prefix string was not a CIDR. `diting_dns64_new` reports it; nothing else can produce it.
const STATUS_PREFIX_PARSE: u32 = 3;
/// A prefix parsed but is not an RFC 6052 length, or the mask is not an IPv6 one.
const STATUS_PREFIX_LENGTH: u32 = 4;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_dns64_abi_version() -> u32 {
    ABI_VERSION
}

/// Builds a synthesizer, writing the handle to `out` and the index of a rejected prefix to
/// `out_index` (left untouched on success).
///
/// # Safety
///
/// `prefixes` must be readable for `prefixes_len` bytes; `out` and `out_index` must be writable.
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

/// Drops a synthesizer created by [`diting_dns64_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_dns64_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_dns64_free(handle: *mut Engine) {
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
pub unsafe extern "C" fn diting_dns64_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Writes the enabled flag and the configured prefix count.
///
/// # Safety
///
/// `handle` must be a live handle; `out_enabled` and `out_prefixes` must be writable.
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

/// `MapIPv4ToIPv6`: writes the 16 synthesized bytes to `out`.
///
/// # Safety
///
/// `v4` must be readable for `v4_len` bytes; `out` must be writable for 16 bytes.
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

/// `EmbedIPv4InIPv6`: the same embedding, driven by the prefix bytes Go already holds.
///
/// `prefix` is the 16-byte `IPNet.IP.To16()` and `ones` its mask length; the Go helper has already
/// rejected 32-bit masks, so a prefix length outside the RFC 6052 set is the only other refusal.
///
/// # Safety
///
/// `prefix` must be readable for 16 bytes, `v4` for `v4_len` bytes, `out` writable for 16 bytes.
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

/// The AAAA addresses for one A record: one per configured prefix, in order.
///
/// # Safety
///
/// `v4` must be readable for `v4_len` bytes; `out_ptr`/`out_len` must be writable.
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

/// `IsExcluded` for one address of 4, 16, 0 (empty) or any other width, matching `net.IP`.
///
/// # Safety
///
/// `address` must be readable for `address_len` bytes; `out` must be writable.
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

/// `HasValidAAAARecords`: `1` when at least one address survives the exclusion set.
///
/// # Safety
///
/// `data` must be readable for `data_len` bytes; `out` must be writable.
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
