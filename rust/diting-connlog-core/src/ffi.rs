use std::slice;

use crate::dedup::ConnLogDedup;
use crate::payload::decode_mark;

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const RESULT_BAD_PAYLOAD: i32 = -1;

#[no_mangle]
pub extern "C" fn diting_connlog_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn diting_connlog_new() -> *mut ConnLogDedup {
    Box::into_raw(Box::new(ConnLogDedup::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_connlog_free(handle: *mut ConnLogDedup) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_connlog_mark(
    handle: *const ConnLogDedup,
    payload: *const u8,
    payload_len: usize,
) -> i32 {
    let Some(kernel) = handle.as_ref() else {
        return 0;
    };
    if payload.is_null() {
        return RESULT_BAD_PAYLOAD;
    }
    let Some(request) = decode_mark(slice::from_raw_parts(payload, payload_len)) else {
        return RESULT_BAD_PAYLOAD;
    };
    if kernel.mark(
        &request.prefix,
        &request.app,
        &request.dest,
        request.port,
        request.protocol,
        &request.reason,
    ) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_connlog_reset(handle: *const ConnLogDedup) -> u32 {
    if let Some(kernel) = handle.as_ref() {
        kernel.reset();
    }
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_connlog_size(handle: *const ConnLogDedup) -> u32 {
    handle.as_ref().map_or(0, ConnLogDedup::size)
}

#[no_mangle]
pub unsafe extern "C" fn diting_connlog_cleared(handle: *const ConnLogDedup) -> u64 {
    handle.as_ref().map_or(0, ConnLogDedup::cleared)
}

#[cfg(test)]
mod tests;
