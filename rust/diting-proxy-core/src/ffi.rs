//! The C ABI `android/engine/proxy_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_proxy_abi_version` | ABI number the loader validates |
//! | `diting_proxy_call` | one request payload in, one response payload out |
//! | `diting_proxy_free_bytes` | drop a payload this library returned |
//!
//! Every operation (config normalization, the five SOCKS5 handshake steps, the reply parser, the
//! datagram framing and the HTTP CONNECT request) goes through the single `call` entry with an
//! opcode, because they all share the same "encode in, decode out" shape. The layouts are in
//! [`crate::payload`].
//!
//! The kernel is stateless: no handle, no clock. Go owns every socket and every decision about
//! when a handshake step runs.

use std::slice;

use crate::payload::{decode_request, encode_response, handle};

/// Must match `proxyABIVersion` in `android/engine/proxy_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_proxy_abi_version() -> u32 {
    ABI_VERSION
}

/// Runs one request and writes the encoded response to `out` / `out_len`.
///
/// The returned status describes the envelope only: `STATUS_OK` means the response payload holds
/// either a result or an operation error (the op errors are ordinary values to Go, not ABI
/// failures).
///
/// # Safety
///
/// `request` must be readable for `request_len` bytes and `out` / `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_proxy_call(
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

/// Frees a payload returned by this library.
///
/// # Safety
///
/// `pointer`/`length` must be a pair this library produced and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_proxy_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

#[cfg(test)]
mod tests;
