//! The C ABI `android/engine/upstream_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_upstream_abi_version` | ABI number the loader validates |
//! | `diting_upstream_tuning` | the transport tuning table (one payload per process) |
//! | `diting_upstream_target` | PLAIN / DoT server → host + port (default port applied) |
//! | `diting_upstream_dial_address` | host + port + bootstrapped IP → `net.JoinHostPort` text |
//! | `diting_upstream_frame` | query → `u16 length` + query, written into the caller's buffer |
//! | `diting_upstream_tcp_response_length` | the 2-byte prefix of a TCP/DoT response |
//! | `diting_upstream_dot_response_length` | the DoT validity rule (0 or > 4096 is invalid) |
//! | `diting_upstream_is_truncated` | the UDP `TC` flag |
//! | `diting_upstream_doq_skip` | 2 when a DoQ prefix declares the exact remainder, else 0 |
//! | `diting_upstream_plain_*_ns` | the plain-UDP retry deadline arithmetic |
//! | `diting_upstream_doh_status_kind` / `doh_should_retry` | DoH classification and retry |
//! | `diting_upstream_strategy` / `is_policy_rejection` | the mode table and the rcode set |
//! | `diting_upstream_pool_*` | the DoT idle pool (one handle per resolver) |
//! | `diting_upstream_free_bytes` | drop a payload this library returned |
//!
//! A null pool handle behaves like an empty pool (dial fresh, never reuse). The stateless calls
//! cannot be answered without the library: the Go resolver reports the load error and the query
//! fails, which is the same contract as the DNS answer kernel.

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

/// Must match `upstreamABIVersion` in `android/engine/upstream_native.go`.
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

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_upstream_abi_version() -> u32 {
    ABI_VERSION
}

/// Writes the tuning payload (`u8 layout | i64 × 17`).
///
/// # Safety
///
/// `out` / `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_upstream_tuning(out: *mut *mut u8, out_len: *mut usize) -> u32 {
    emit(&encode_tuning(&TUNING), out, out_len)
}

/// Splits one PLAIN / DoT server into host and port (`u8 layout | text host | text port`).
///
/// # Safety
///
/// `server` must be readable for `server_len` bytes; `out` / `out_len` writable.
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

/// Builds the dial address from the split target and the (optional) bootstrapped IP.
///
/// # Safety
///
/// All three slices must be readable for their stated lengths; `out` / `out_len` writable.
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

/// Writes `u16 length` + query into the caller's buffer.
///
/// Returns the bytes written, `-1` on a bad argument or `-2` when `out_cap` is too small.
///
/// # Safety
///
/// `query` must be readable for `query_len` bytes and `out` writable for `out_cap` bytes.
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

/// The 2-byte length prefix of a TCP/DoT response, or `-1` when fewer than two bytes were given.
///
/// # Safety
///
/// `header` must be readable for `header_len` bytes.
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

/// The DoT response length rule: `0` valid (length in `out_len`), `1` invalid (length in `out_len`),
/// `2` bad argument.
///
/// # Safety
///
/// `header` must be readable for `header_len` bytes and `out_len` writable.
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

/// The UDP `TC` flag: `1` set, `0` clear, `-1` bad argument.
///
/// # Safety
///
/// `raw` must be readable for `raw_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_upstream_is_truncated(raw: *const u8, raw_len: usize) -> i32 {
    let Some(raw) = bytes_argument(raw, raw_len) else {
        return -1;
    };
    i32::from(is_truncated(raw))
}

/// How many bytes of a DoQ response to skip (0 or 2).
///
/// # Safety
///
/// `raw` must be readable for `raw_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_upstream_doq_skip(raw: *const u8, raw_len: usize) -> u32 {
    let Some(raw) = bytes_argument(raw, raw_len) else {
        return 0;
    };
    doq_skip(raw) as u32
}

/// `plainUDPRetryDelayFromContext`: a positive caller value wins, otherwise the tuning default.
#[no_mangle]
pub extern "C" fn diting_upstream_plain_initial_delay_ns(ctx_value_ns: i64) -> i64 {
    initial_retry_delay_ns(ctx_value_ns)
}

/// The first read deadline of a plain UDP query.
#[no_mangle]
pub extern "C" fn diting_upstream_plain_first_deadline_ns(
    now_ns: i64,
    initial_ns: i64,
    deadline_ns: i64,
) -> i64 {
    first_deadline_ns(now_ns, initial_ns, deadline_ns)
}

/// The next plain-UDP retry deadline: `0` no retry, `1` retry (deadline in `out_deadline`),
/// `2` bad argument.
///
/// # Safety
///
/// `out_deadline` must be writable.
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

/// DoH status classification: `0` body, `1` rate limited (403), `2` other status.
#[no_mangle]
pub extern "C" fn diting_upstream_doh_status_kind(status: i32) -> u32 {
    match status_kind(status) {
        StatusKind::Ok => 0,
        StatusKind::RateLimited => 1,
        StatusKind::Other => 2,
    }
}

/// Whether a failed DoH attempt should be retried: `1` yes, `0` no, `-1` bad argument.
///
/// # Safety
///
/// `error_text` must be readable for `error_len` bytes.
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

/// The provider-mode table: `0` single, `1` primary_backup, `2` parallel_race, `3` smart_prediction.
///
/// # Safety
///
/// `mode` must be readable for `mode_len` bytes.
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

/// Whether an upstream rcode is a policy rejection (REFUSED / FORMERR / NOTIMP).
#[no_mangle]
pub extern "C" fn diting_upstream_is_policy_rejection(rcode: i32) -> i32 {
    i32::from(is_policy_rejection(rcode))
}

// --- DoT idle pool ----------------------------------------------------------------------------

/// Creates one resolver's idle pool.
#[no_mangle]
pub extern "C" fn diting_upstream_pool_new() -> *mut DotPool {
    Box::into_raw(Box::new(DotPool::new()))
}

/// Drops a pool handle.
///
/// # Safety
///
/// `handle` must come from [`diting_upstream_pool_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_upstream_pool_free(handle: *mut DotPool) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Pops the next candidate: `0` empty, `1` idle (probe it), `2` expired (close it), `-1` bad
/// argument. The id is written to `out_id` for `1` and `2`.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes and `out_id` writable.
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

/// Whether the connection was kept: `1` kept, `0` the caller closes it, `-1` bad argument.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes.
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

/// Every pooled id (`u8 layout | u32 count | u64 ids`); the pool is emptied.
///
/// # Safety
///
/// `out` / `out_len` must be writable.
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

/// Idle entries for one target.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes.
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

/// Drops a payload a call returned.
///
/// # Safety
///
/// `pointer` / `length` must be exactly what a call returned, and must not be freed twice.
#[no_mangle]
pub unsafe extern "C" fn diting_upstream_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

/// Hands an encoded payload to the caller, as a boxed slice Go frees with its length.
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

/// Reads a required UTF-8 text argument. A zero length is the empty string.
unsafe fn text_argument<'a>(text: *const u8, len: usize) -> Option<&'a str> {
    let bytes = bytes_argument(text, len)?;
    str::from_utf8(bytes).ok()
}

/// Reads a byte argument. A zero length is the empty slice, even for a null pointer.
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
