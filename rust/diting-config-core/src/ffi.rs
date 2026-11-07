//! The C ABI `android/engine/config_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_config_abi_version` | ABI number the loader validates |
//! | `diting_config_call` | one request payload in, one response payload out |
//! | `diting_config_free_bytes` | drop a payload this library returned |
//!
//! Every operation goes through the single `call` entry with an opcode, because they all share the
//! same "encode in, decode out" shape: one DNS config, one protocol or block-response name, one DoQ
//! endpoint, one domain key, one rewrite target list. The layouts are in [`crate::payload`].
//!
//! The kernel is stateless: no handle, no clock, no file. Go keeps the decoded JSON, the `Engine`
//! state, the resolver / cache hand-off and every log line.

use std::slice;

use crate::payload::{decode_request, encode_response, handle};

/// Must match `configABIVersion` in `android/engine/config_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_config_abi_version() -> u32 {
    ABI_VERSION
}

/// Runs one request and writes the encoded response to `out` / `out_len`.
///
/// The returned status describes the envelope only: `STATUS_OK` means the response payload holds
/// either a result or a config error (the error text is an ordinary value to Go, not an ABI
/// failure).
///
/// # Safety
///
/// `request` must be readable for `request_len` bytes and `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_config_call(
    request: *const u8,
    request_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() || (request.is_null() && request_len != 0) {
        return STATUS_BAD_ARGUMENT;
    }
    let payload = if request_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(request, request_len)
    };
    let Some(decoded) = decode_request(payload) else {
        return STATUS_BAD_PAYLOAD;
    };
    let encoded = encode_response(handle(decoded));
    // A boxed slice so the allocation's capacity is its length: Go frees it with that length.
    let mut boxed = encoded.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

/// Drops a payload [`diting_config_call`] returned.
///
/// # Safety
///
/// `pointer` / `length` must be exactly what the call returned, and must not be freed twice.
#[no_mangle]
pub unsafe extern "C" fn diting_config_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

#[cfg(test)]
mod tests;
