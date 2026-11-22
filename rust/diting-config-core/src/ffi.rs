use std::slice;

use crate::payload::{decode_request, encode_response, handle};

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

#[no_mangle]
pub extern "C" fn diting_config_abi_version() -> u32 {
    ABI_VERSION
}

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
    let mut boxed = encoded.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

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
