//! The C ABI `android/engine/mitm_sniffer_native.go` loads with cgo.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_sniffer_abi_version` | ABI number the loader validates |
//! | `diting_sniffer_classify` | classify one peeked flow, as a layout-prefixed payload |
//! | `diting_sniffer_free_bytes` | drop a payload this library returned |
//!
//! Status codes:
//!
//! * `0` — ok
//! * `1` — bad argument (null pointer where a buffer or output slot was required)
//!
//! A payload is always written on success, even for `unknown` with an empty host, so the Go caller
//! has a single decode path.

use std::slice;

use crate::classify;
use crate::payload::encode;

/// Must match `snifferNativeABIVersion` in `android/engine/mitm_sniffer_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_sniffer_abi_version() -> u32 {
    ABI_VERSION
}

/// Classifies the `length` bytes at `data` and hands the result to Go.
///
/// The payload is `u8 layout | u8 kind | u32 host_len | host bytes`; Go copies it and calls
/// [`diting_sniffer_free_bytes`].
///
/// # Safety
///
/// `data` must be readable for `length` bytes; `out` and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_sniffer_classify(
    data: *const u8,
    length: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(data) = slice_from(data, length) else {
        return STATUS_BAD_ARGUMENT;
    };
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let sniffed = classify(data);
    // A boxed slice so the allocation's capacity is its length: Go frees it with that length.
    let mut payload = encode(sniffed.kind as u8, &sniffed.host).into_boxed_slice();
    let payload_len = payload.len();
    let pointer = payload.as_mut_ptr();
    std::mem::forget(payload);
    *out = pointer;
    *out_len = payload_len;
    STATUS_OK
}

/// Frees a payload [`diting_sniffer_classify`] returned.
///
/// # Safety
///
/// `pointer`/`length` must be exactly what this library returned, freed once.
#[no_mangle]
pub unsafe extern "C" fn diting_sniffer_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, length, length));
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

#[cfg(test)]
mod tests;
