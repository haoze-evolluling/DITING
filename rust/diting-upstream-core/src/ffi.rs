use std::slice;
use std::str;

use crate::doh::{should_retry, status_kind, StatusKind};
use crate::endpoint::{dial_address, split_target, TargetProtocol};
use crate::framing::{
    doq_skip, dot_response_length, first_deadline_ns, frame_into, initial_retry_delay_ns,
    is_truncated, retry_deadline_ns, tcp_response_length, DotLength,
};
use crate::payload::{encode_address, encode_ids, encode_target, encode_tuning};
use crate::plan::{is_policy_rejection, strategy, Strategy};
use crate::pool::{Acquired, DotPool};
use crate::tuning::TUNING;

pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;

const PROTOCOL_PLAIN: u32 = 0;
const PROTOCOL_DOT: u32 = 1;

const ACQUIRE_EMPTY: i32 = 0;
const ACQUIRE_IDLE: i32 = 1;
const ACQUIRE_EXPIRED: i32 = 2;

const RESULT_BAD_ARGUMENT: isize = -1;
const RESULT_TOO_SMALL: isize = -2;

#[no_mangle]
pub extern "C" fn diting_upstream_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_tuning(out: *mut *mut u8, out_len: *mut usize) -> u32 {
    emit(&encode_tuning(&TUNING), out, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_target(
    protocol: u32,
    server: *const u8,
    server_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let protocol = match protocol {
        PROTOCOL_PLAIN => TargetProtocol::Plain,
        PROTOCOL_DOT => TargetProtocol::Dot,
        _ => return STATUS_BAD_ARGUMENT,
    };
    let Some(server) = text_argument(server, server_len) else {
        return STATUS_BAD_ARGUMENT;
    };
    let (host, port) = split_target(server, protocol);
    emit(&encode_target(&host, &port), out, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_dial_address(
    host: *const u8,
    host_len: usize,
    port: *const u8,
    port_len: usize,
    bootstrapped: *const u8,
    bootstrapped_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let (Some(host), Some(port), Some(bootstrapped)) = (
        text_argument(host, host_len),
        text_argument(port, port_len),
        text_argument(bootstrapped, bootstrapped_len),
    ) else {
        return STATUS_BAD_ARGUMENT;
    };
    emit(
        &encode_address(&dial_address(host, port, bootstrapped)),
        out,
        out_len,
    )
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_frame(
    query: *const u8,
    query_len: usize,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let Some(query) = bytes_argument(query, query_len) else {
        return RESULT_BAD_ARGUMENT;
    };
    if out.is_null() {
        return RESULT_BAD_ARGUMENT;
    }
    let target = slice::from_raw_parts_mut(out, out_cap);
    match frame_into(query, target) {
        Some(written) => written as isize,
        None => RESULT_TOO_SMALL,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_tcp_response_length(
    header: *const u8,
    header_len: usize,
) -> i32 {
    let Some(header) = bytes_argument(header, header_len) else {
        return -1;
    };
    match tcp_response_length(header) {
        Some(length) => length as i32,
        None => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_dot_response_length(
    header: *const u8,
    header_len: usize,
    out_len: *mut u32,
) -> u32 {
    if out_len.is_null() {
        return 2;
    }
    let Some(header) = bytes_argument(header, header_len) else {
        return 2;
    };
    match dot_response_length(header) {
        Some(DotLength::Valid(length)) => {
            *out_len = length as u32;
            STATUS_OK
        }
        Some(DotLength::Invalid(length)) => {
            *out_len = length as u32;
            1
        }
        None => 2,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_is_truncated(raw: *const u8, raw_len: usize) -> i32 {
    let Some(raw) = bytes_argument(raw, raw_len) else {
        return -1;
    };
    i32::from(is_truncated(raw))
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_doq_skip(raw: *const u8, raw_len: usize) -> u32 {
    let Some(raw) = bytes_argument(raw, raw_len) else {
        return 0;
    };
    doq_skip(raw) as u32
}

#[no_mangle]
pub extern "C" fn diting_upstream_plain_initial_delay_ns(ctx_value_ns: i64) -> i64 {
    initial_retry_delay_ns(ctx_value_ns)
}

#[no_mangle]
pub extern "C" fn diting_upstream_plain_first_deadline_ns(
    now_ns: i64,
    initial_ns: i64,
    deadline_ns: i64,
) -> i64 {
    first_deadline_ns(now_ns, initial_ns, deadline_ns)
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_plain_retry_deadline_ns(
    now_ns: i64,
    initial_ns: i64,
    deadline_ns: i64,
    retry_index: u32,
    out_deadline: *mut i64,
) -> u32 {
    if out_deadline.is_null() {
        return 2;
    }
    match retry_deadline_ns(now_ns, initial_ns, deadline_ns, retry_index) {
        Some(deadline) => {
            *out_deadline = deadline;
            1
        }
        None => 0,
    }
}

#[no_mangle]
pub extern "C" fn diting_upstream_doh_status_kind(status: i32) -> u32 {
    match status_kind(status) {
        StatusKind::Ok => 0,
        StatusKind::RateLimited => 1,
        StatusKind::Other => 2,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_doh_should_retry(
    attempt: u32,
    error_text: *const u8,
    error_len: usize,
) -> i32 {
    let Some(error_text) = text_argument(error_text, error_len) else {
        return -1;
    };
    i32::from(should_retry(attempt, error_text))
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_strategy(mode: *const u8, mode_len: usize) -> u32 {
    let Some(mode) = text_argument(mode, mode_len) else {
        return 0;
    };
    match strategy(mode) {
        Strategy::Single => 0,
        Strategy::PrimaryBackup => 1,
        Strategy::ParallelRace => 2,
        Strategy::SmartPrediction => 3,
    }
}

#[no_mangle]
pub extern "C" fn diting_upstream_is_policy_rejection(rcode: i32) -> i32 {
    i32::from(is_policy_rejection(rcode))
}


#[no_mangle]
pub extern "C" fn diting_upstream_pool_new() -> *mut DotPool {
    Box::into_raw(Box::new(DotPool::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_pool_free(handle: *mut DotPool) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_pool_acquire(
    handle: *const DotPool,
    host: *const u8,
    host_len: usize,
    now_ms: i64,
    out_id: *mut u64,
) -> i32 {
    let Some(pool) = handle.as_ref() else {
        return ACQUIRE_EMPTY;
    };
    if out_id.is_null() {
        return -1;
    }
    let Some(host) = text_argument(host, host_len) else {
        return -1;
    };
    match pool.acquire(host, now_ms) {
        None => ACQUIRE_EMPTY,
        Some(Acquired::Idle(id)) => {
            *out_id = id;
            ACQUIRE_IDLE
        }
        Some(Acquired::Expired(id)) => {
            *out_id = id;
            ACQUIRE_EXPIRED
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_pool_release(
    handle: *const DotPool,
    host: *const u8,
    host_len: usize,
    id: u64,
    now_ms: i64,
) -> i32 {
    let Some(pool) = handle.as_ref() else {
        return 0;
    };
    let Some(host) = text_argument(host, host_len) else {
        return -1;
    };
    i32::from(pool.release(host, id, now_ms))
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_pool_close_all(
    handle: *const DotPool,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(pool) = handle.as_ref() else {
        return emit(&encode_ids(&[]), out, out_len);
    };
    emit(&encode_ids(&pool.close_all()), out, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_pool_len(
    handle: *const DotPool,
    host: *const u8,
    host_len: usize,
) -> u32 {
    let Some(pool) = handle.as_ref() else {
        return 0;
    };
    let Some(host) = text_argument(host, host_len) else {
        return 0;
    };
    pool.len(host)
}

#[no_mangle]
pub unsafe extern "C" fn diting_upstream_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

unsafe fn emit(encoded: &[u8], out: *mut *mut u8, out_len: *mut usize) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let mut boxed = encoded.to_vec().into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

unsafe fn text_argument<'a>(text: *const u8, len: usize) -> Option<&'a str> {
    let bytes = bytes_argument(text, len)?;
    str::from_utf8(bytes).ok()
}

unsafe fn bytes_argument<'a>(bytes: *const u8, len: usize) -> Option<&'a [u8]> {
    if len == 0 {
        return Some(&[]);
    }
    if bytes.is_null() {
        return None;
    }
    Some(slice::from_raw_parts(bytes, len))
}

#[cfg(test)]
mod tests;
