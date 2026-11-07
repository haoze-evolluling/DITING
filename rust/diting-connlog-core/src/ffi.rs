//! The C ABI `android/engine/connlog_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_connlog_abi_version` | ABI number the loader validates |
//! | `diting_connlog_new` | the process-wide dedupe set |
//! | `diting_connlog_free` | drop a handle |
//! | `diting_connlog_mark` | build the key from the payload and report a duplicate |
//! | `diting_connlog_reset` | a new full-tunnel session empties the set (`cleared` is kept) |
//! | `diting_connlog_size` | current entry count |
//! | `diting_connlog_cleared` | number of overflow resets so far |
//!
//! A null handle reports "not a duplicate" and zero counters, which matches "deduplication
//! disabled": every log line is emitted.

use std::slice;

use crate::dedup::ConnLogDedup;
use crate::payload::decode_mark;

/// Must match `connLogABIVersion` in `android/engine/connlog_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const RESULT_BAD_PAYLOAD: i32 = -1;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_connlog_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates the dedupe set.
#[no_mangle]
pub extern "C" fn diting_connlog_new() -> *mut ConnLogDedup {
    Box::into_raw(Box::new(ConnLogDedup::new()))
}

/// Drops a handle created by [`diting_connlog_new`].
///
/// # Safety
///
/// `handle` must come from `diting_connlog_new` and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_connlog_free(handle: *mut ConnLogDedup) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// `connLogKey` + `markSeen`: returns 1 when the key was already present, 0 when it was inserted,
/// -1 on a bad payload.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes.
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

/// `reset`: empty the set.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_connlog_reset(handle: *const ConnLogDedup) -> u32 {
    if let Some(kernel) = handle.as_ref() {
        kernel.reset();
    }
    STATUS_OK
}

/// `size`.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_connlog_size(handle: *const ConnLogDedup) -> u32 {
    handle.as_ref().map_or(0, ConnLogDedup::size)
}

/// `cleared`: overflow resets so far.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_connlog_cleared(handle: *const ConnLogDedup) -> u64 {
    handle.as_ref().map_or(0, ConnLogDedup::cleared)
}

#[cfg(test)]
mod tests;
