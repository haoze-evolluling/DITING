use std::slice;

use crate::classify;
use crate::payload::encode;

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_sniffer_abi_version() -> u32 {
    ABI_VERSION
}

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
    let mut payload = encode(sniffed.kind as u8, &sniffed.host).into_boxed_slice();
    let payload_len = payload.len();
    let pointer = payload.as_mut_ptr();
    std::mem::forget(payload);
    *out = pointer;
    *out_len = payload_len;
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_sniffer_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, length, length));
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
