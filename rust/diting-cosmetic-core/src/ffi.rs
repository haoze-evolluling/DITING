//! The C ABI `android/engine/mitm_cosmetic_native.go` loads with cgo.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_cosmetic_abi_version` | ABI number the loader validates |
//! | `diting_cosmetic_new` | open a scanner for one already-built `<link>` tag |
//! | `diting_cosmetic_free` | drop one |
//! | `diting_cosmetic_pending` | serve queued bytes into the caller's buffer |
//! | `diting_cosmetic_process` | post-process the bytes one upstream `Read` produced |
//! | `diting_cosmetic_normalize_host` | `normalizeCosmeticHost`, as a layout-prefixed payload |
//! | `diting_cosmetic_link_tag` | `cosmeticLinkTag`, as a layout-prefixed payload |
//! | `diting_cosmetic_rules_new` | compile one `SetCosmeticRules` decode into a handle |
//! | `diting_cosmetic_rules_free` | drop one |
//! | `diting_cosmetic_rules_render` | `buildCosmeticCss`: the stylesheet for one page host |
//! | `diting_cosmetic_host_suffixes` | `hostSuffixes`, as a text-list payload |
//! | `diting_cosmetic_is_asset_host` | `IsLocalAssetHost` |
//! | `diting_cosmetic_local_response` | `ServeLocalAsset`: route, headers and body |
//! | `diting_cosmetic_free_bytes` | drop a payload this library returned |
//!
//! Status codes, shared by every function:
//!
//! * `0` — ok
//! * `1` — bad argument (null handle or pointer)
//! * `2` — a layout-prefixed payload did not decode
//!
//! `diting_cosmetic_process` writes two results: how many bytes the caller should report, and
//! whether the upstream error travels with them. The handle is only touched by one goroutine at a
//! time — a response body has one reader — so there is no lock inside.

use std::slice;

use crate::host::{link_tag, normalize_host};
use crate::inject::{Injector, Outcome, Upstream};
use crate::local::{is_asset_host, respond};
use crate::payload::{decode_rules, decode_text, encode_response, encode_text, encode_text_list};
use crate::rules::{host_suffixes, RuleSet};

/// Must match `cosmeticNativeABIVersion` in `android/engine/mitm_cosmetic_native.go`.
///
/// 2 added the rule-set handle, the stylesheet render, the host suffixes, `IsLocalAssetHost` and the
/// local asset server's response.
pub const ABI_VERSION: u32 = 2;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
/// The layout-prefixed `<link>` payload did not decode.
const STATUS_BAD_PAYLOAD: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_cosmetic_abi_version() -> u32 {
    ABI_VERSION
}

/// Builds the `<link>` tag for `host` under `asset_host` and returns it as a payload.
///
/// # Safety
///
/// `host`/`asset_host` must be readable for their lengths; `out` and `out_len` must be writable.
/// The payload is released with [`diting_cosmetic_free_bytes`].
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
    // A boxed slice so the allocation's capacity is its length: Go frees it with that length.
    write_text(out, out_len, link_tag(&host, &asset_host).as_bytes())
}

/// `normalizeCosmeticHost`: lowercase, trim, drop the port, strip one trailing dot.
///
/// The local asset server uses this to look up the rules for `?h=<host>`; keeping it in the kernel
/// is what stops the served stylesheet and the injected link from disagreeing on the hostname.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes; `out` and `out_len` must be writable. The payload is
/// released with [`diting_cosmetic_free_bytes`].
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

/// Compiles one decoded rule set into a handle.
///
/// The payload is Go's `encoding/json` result (see [`crate::payload`]); the handle owns the selector
/// lists so a `/cosmetic.css` request does not re-decode anything.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes; `out` must be writable.
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

/// Drops a rule-set handle.
///
/// # Safety
///
/// `handle` must come from [`diting_cosmetic_rules_new`] and be freed once.
#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_rules_free(handle: *mut RuleSet) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle));
}

/// `buildCosmeticCss`: the stylesheet for `host`, as a text payload.
///
/// A null handle renders the empty-payload sentinel, so a server that never received rules still
/// answers with a valid stylesheet.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes; `out` / `out_len` must be writable.
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

/// `hostSuffixes`: the host and each parent domain, as a text-list payload.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes; `out` / `out_len` must be writable.
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

/// `IsLocalAssetHost`: `1` when the flow belongs to the local asset server, else `0`.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_is_asset_host(host: *const u8, host_len: usize) -> i32 {
    let Some(host) = text(host, host_len) else {
        return 0;
    };
    i32::from(is_asset_host(&host))
}

/// `ServeLocalAsset`: the response payload for one request.
///
/// `payload_bytes` is the raw rule payload size `/health` reports. A null handle behaves like an
/// empty rule set, so the stylesheet is the "no cosmetic rules loaded" sentinel.
///
/// # Safety
///
/// `path` and `host_query` must be readable for their lengths; `out` / `out_len` must be writable.
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

/// Hands an encoded payload to Go, which copies it and calls [`diting_cosmetic_free_bytes`].
///
/// # Safety
///
/// `out` and `out_len` must be writable.
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

/// Hands a boxed text payload to Go, which copies it and calls [`diting_cosmetic_free_bytes`].
fn write_text(out: *mut *mut u8, out_len: *mut usize, text: &[u8]) -> u32 {
    // A boxed slice so the allocation's capacity is its length: Go frees it with that length.
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

/// Frees a payload [`diting_cosmetic_link_tag`] returned.
///
/// # Safety
///
/// `pointer`/`length` must be exactly what this library returned, freed once.
#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, length, length));
}

/// Opens a scanner whose `<link>` tag is the layout-prefixed payload in `link`.
///
/// # Safety
///
/// `link` must be readable for `link_len` bytes; `out` must be writable.
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

/// Drops a scanner.
///
/// # Safety
///
/// `handle` must come from [`diting_cosmetic_new`] and be freed once.
#[no_mangle]
pub unsafe extern "C" fn diting_cosmetic_free(handle: *mut Injector) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle));
}

/// Serves queued bytes into `buffer`, returning how many were written.
///
/// # Safety
///
/// `handle` must be live; `buffer` must be writable for `capacity` bytes.
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

/// Post-processes the `n` bytes an upstream `Read` wrote into `buffer`.
///
/// `flags` carries [`crate::inject::UPSTREAM_ERRORED`] / [`crate::inject::UPSTREAM_EOF`]. On success
/// `out_len` receives the byte count to report and `out_keep_error` whether the upstream error
/// should travel with it (0 = report success so the queue can drain).
///
/// # Safety
///
/// `handle` must be live; `buffer` must be writable for `capacity` bytes; `out_len` and
/// `out_keep_error` must be writable.
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

/// The bytes behind `pointer`/`length`, or `None` for a null pointer.
///
/// # Safety
///
/// The caller guarantees the range is readable when it is not empty.
unsafe fn slice_from<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        return Some(&[]);
    }
    if pointer.is_null() {
        return None;
    }
    Some(slice::from_raw_parts(pointer, length))
}

/// The writable range behind `pointer`/`capacity`, or `None` for a null pointer.
///
/// # Safety
///
/// The caller guarantees the range is writable when it is not empty.
unsafe fn buffer_range<'a>(pointer: *mut u8, capacity: usize) -> Option<&'a mut [u8]> {
    if capacity == 0 {
        return Some(&mut []);
    }
    if pointer.is_null() {
        return None;
    }
    Some(slice::from_raw_parts_mut(pointer, capacity))
}

/// Go strings are bytes; a hostname that is not UTF-8 is decoded lossily rather than rejected, so a
/// garbage `Host` header still yields a tag instead of an error the relay cannot act on.
unsafe fn text(pointer: *const u8, length: usize) -> Option<String> {
    let bytes = slice_from(pointer, length)?;
    Some(String::from_utf8_lossy(bytes).into_owned())
}

#[cfg(test)]
mod tests;
