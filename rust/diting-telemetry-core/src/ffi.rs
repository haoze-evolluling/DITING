//! The C ABI `android/engine/telemetry_native.go` loads with `dlopen`.
//!
//! Four handles, one per Go wrapper, so lifetimes stay independent:
//!
//! | symbol prefix | handle | Go owner |
//! | --- | --- | --- |
//! | `diting_telemetry_log_*` | DNS log batch buffer | `logAggregator` |
//! | `diting_telemetry_traffic_*` | per-UID byte counters | `TrafficTracker` |
//! | `diting_telemetry_flow_*` | 5-tuple → UID cache | `cachingUIDResolver` |
//! | `diting_telemetry_package_*` | UID → package cache | `cachingAppUidResolver` |
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_telemetry_abi_version` | ABI number the loader validates |
//! | `*_new` / `*_free` | handle lifecycle (the Go side holds a finalizer) |
//! | `log_push` / `log_drain` / `log_pending` / `log_dropped` / `log_dropped_conn` | batch buffer |
//! | `traffic_record` / `traffic_tick` / `traffic_set_interval_ms` / `traffic_interval_ms` / `traffic_unique_uids` / `traffic_totals` | byte counters |
//! | `flow_lookup` / `flow_store` / `flow_len` | flow attribution |
//! | `package_lookup` / `package_store` / `package_len` | package attribution |
//! | `diting_telemetry_free_bytes` | drop a payload this library returned |
//!
//! A null handle is the "kernel unavailable" shape: pushes are dropped, ticks are empty, lookups
//! miss. The Go wrappers degrade along the same lines they documented before the kernel existed, so
//! a missing library never changes a DNS answer.

use std::slice;

use crate::logagg::{LogAggregator, PushOutcome};
use crate::payload::{
    decode_flow_lookup, decode_flow_store, decode_log_push, encode_log_batch, encode_traffic_tick,
};
use crate::traffic::TrafficTracker;
use crate::uidcache::{FlowUidCache, UidPackageCache};

/// Must match `telemetryABIVersion` in `android/engine/telemetry_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

const PUSH_DROPPED: i32 = 0;
const PUSH_BUFFERED: i32 = 1;
const PUSH_FULL: i32 = 2;
const PUSH_BAD_PAYLOAD: i32 = -1;
const PUSH_NULL_HANDLE: i32 = -2;

const LOOKUP_HIT: i32 = 1;
const LOOKUP_MISS: i32 = 0;
const LOOKUP_BAD_PAYLOAD: i32 = -1;
const LOOKUP_NULL_HANDLE: i32 = -2;

const TEXT_MISS: isize = -1;
const TEXT_BAD_ARGUMENT: isize = -2;
const TEXT_TOO_SMALL: isize = -3;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_telemetry_abi_version() -> u32 {
    ABI_VERSION
}

// --- log batch buffer -------------------------------------------------------------------------

/// Creates the DNS log buffer.
#[no_mangle]
pub extern "C" fn diting_telemetry_log_new() -> *mut LogAggregator {
    Box::into_raw(Box::new(LogAggregator::new()))
}

/// Drops a log buffer handle.
///
/// # Safety
///
/// `handle` must come from [`diting_telemetry_log_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_free(handle: *mut LogAggregator) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Queues one row: `0` dropped, `1` buffered, `2` a full batch is waiting, `-1` bad payload,
/// `-2` null handle.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_push(
    handle: *const LogAggregator,
    payload: *const u8,
    payload_len: usize,
) -> i32 {
    let Some(aggregator) = handle.as_ref() else {
        return PUSH_NULL_HANDLE;
    };
    if payload.is_null() {
        return PUSH_BAD_PAYLOAD;
    }
    let Some(item) = decode_log_push(slice::from_raw_parts(payload, payload_len)) else {
        return PUSH_BAD_PAYLOAD;
    };
    match aggregator.push(item) {
        PushOutcome::Dropped => PUSH_DROPPED,
        PushOutcome::Buffered => PUSH_BUFFERED,
        PushOutcome::Full => PUSH_FULL,
    }
}

/// Takes up to `max` rows; the returned payload is `u8 layout | u32 count | rows`.
///
/// # Safety
///
/// `out` / `out_len` must be writable and the handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_drain(
    handle: *const LogAggregator,
    max: u32,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if handle.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let (items, _) = (*handle).drain(max as usize);
    emit(encode_log_batch(&items), out, out_len)
}

/// Rows waiting for a flush.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_pending(handle: *const LogAggregator) -> u32 {
    handle
        .as_ref()
        .map_or(0, |aggregator| aggregator.pending() as u32)
}

/// `droppedLogs`.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_dropped(handle: *const LogAggregator) -> u64 {
    handle.as_ref().map_or(0, LogAggregator::dropped)
}

/// `droppedConnLogs`.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_dropped_conn(handle: *const LogAggregator) -> u64 {
    handle.as_ref().map_or(0, LogAggregator::dropped_conn)
}

// --- traffic counters -------------------------------------------------------------------------

/// Creates the per-UID traffic counters.
#[no_mangle]
pub extern "C" fn diting_telemetry_traffic_new() -> *mut TrafficTracker {
    Box::into_raw(Box::new(TrafficTracker::new()))
}

/// Drops a traffic handle.
///
/// # Safety
///
/// `handle` must come from [`diting_telemetry_traffic_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_free(handle: *mut TrafficTracker) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// `RecordTx` + `RecordRx`: non-positive counts and `uid <= 0` are ignored.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_record(
    handle: *const TrafficTracker,
    uid: i32,
    tx: i64,
    rx: i64,
) -> u32 {
    let Some(tracker) = handle.as_ref() else {
        return STATUS_BAD_ARGUMENT;
    };
    tracker.record(uid, tx, rx);
    STATUS_OK
}

/// Swaps the deltas out; the payload is `u8 layout | u32 count | (i32 uid, u64 tx, u64 rx)`.
///
/// # Safety
///
/// `out` / `out_len` must be writable and the handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_tick(
    handle: *const TrafficTracker,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if handle.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    emit(encode_traffic_tick(&(*handle).tick()), out, out_len)
}

/// `SetTickInterval`: a non-positive interval keeps the current cadence.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_set_interval_ms(
    handle: *const TrafficTracker,
    interval_ms: i64,
) -> u32 {
    let Some(tracker) = handle.as_ref() else {
        return STATUS_BAD_ARGUMENT;
    };
    tracker.set_interval_ms(interval_ms);
    STATUS_OK
}

/// The cadence the Go ticker arms its timer with.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_interval_ms(
    handle: *const TrafficTracker,
) -> i64 {
    handle.as_ref().map_or(0, TrafficTracker::interval_ms)
}

/// How many UIDs have counters.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_unique_uids(
    handle: *const TrafficTracker,
) -> u32 {
    handle.as_ref().map_or(0, TrafficTracker::unique_uids)
}

/// Reads one UID's totals: `0` written, `1` unknown UID, `2` bad argument.
///
/// # Safety
///
/// Both out pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_totals(
    handle: *const TrafficTracker,
    uid: i32,
    out_tx: *mut u64,
    out_rx: *mut u64,
) -> u32 {
    if handle.is_null() || out_tx.is_null() || out_rx.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    match (*handle).totals(uid) {
        Some((tx, rx)) => {
            *out_tx = tx;
            *out_rx = rx;
            STATUS_OK
        }
        None => 1,
    }
}

// --- flow attribution cache -------------------------------------------------------------------

/// Creates the flow → UID cache.
#[no_mangle]
pub extern "C" fn diting_telemetry_flow_new() -> *mut FlowUidCache {
    Box::into_raw(Box::new(FlowUidCache::new()))
}

/// Drops a flow cache handle.
///
/// # Safety
///
/// `handle` must come from [`diting_telemetry_flow_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_flow_free(handle: *mut FlowUidCache) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// `resolveFlow`'s lookup: `1` hit (UID in `out_uid`), `0` miss, `-1` bad payload, `-2` null.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes and `out_uid` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_flow_lookup(
    handle: *const FlowUidCache,
    payload: *const u8,
    payload_len: usize,
    out_uid: *mut i32,
) -> i32 {
    let Some(cache) = handle.as_ref() else {
        return LOOKUP_NULL_HANDLE;
    };
    if payload.is_null() || out_uid.is_null() {
        return LOOKUP_BAD_PAYLOAD;
    }
    let Some((key, now_ns)) = decode_flow_lookup(slice::from_raw_parts(payload, payload_len))
    else {
        return LOOKUP_BAD_PAYLOAD;
    };
    match cache.lookup(&key, now_ns) {
        Some(uid) => {
            *out_uid = uid;
            LOOKUP_HIT
        }
        None => LOOKUP_MISS,
    }
}

/// `resolveFlow`'s insert: `0` stored, `1` bad payload, `2` null handle.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_flow_store(
    handle: *const FlowUidCache,
    payload: *const u8,
    payload_len: usize,
) -> u32 {
    if handle.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    if payload.is_null() {
        return STATUS_BAD_PAYLOAD;
    }
    let Some((key, now_ns, uid)) = decode_flow_store(slice::from_raw_parts(payload, payload_len))
    else {
        return STATUS_BAD_PAYLOAD;
    };
    (*handle).store(key, uid, now_ns);
    STATUS_OK
}

/// Current flow entry count.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_flow_len(handle: *const FlowUidCache) -> u32 {
    handle.as_ref().map_or(0, FlowUidCache::len)
}

// --- package attribution cache ----------------------------------------------------------------

/// Creates the UID → package cache.
#[no_mangle]
pub extern "C" fn diting_telemetry_package_new() -> *mut UidPackageCache {
    Box::into_raw(Box::new(UidPackageCache::new()))
}

/// Drops a package cache handle.
///
/// # Safety
///
/// `handle` must come from [`diting_telemetry_package_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_package_free(handle: *mut UidPackageCache) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// `PackageForUid`'s lookup: writes the name and returns its length, or `-1` on a miss,
/// `-2` on a bad argument and `-3` when the caller's buffer is too small.
///
/// # Safety
///
/// `out` must be writable for `out_cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_package_lookup(
    handle: *const UidPackageCache,
    uid: i32,
    now_ns: i64,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let Some(cache) = handle.as_ref() else {
        return TEXT_MISS;
    };
    if out.is_null() {
        return TEXT_BAD_ARGUMENT;
    }
    match cache.lookup(uid, now_ns) {
        None => TEXT_MISS,
        Some(name) => {
            if out_cap < name.len() {
                return TEXT_TOO_SMALL;
            }
            std::ptr::copy_nonoverlapping(name.as_ptr(), out, name.len());
            name.len() as isize
        }
    }
}

/// `PackageForUid`'s insert: empty names are not cached.
///
/// # Safety
///
/// `name` must be readable for `name_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_package_store(
    handle: *const UidPackageCache,
    uid: i32,
    name: *const u8,
    name_len: usize,
    now_ns: i64,
) -> u32 {
    if handle.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    if name.is_null() && name_len != 0 {
        return STATUS_BAD_ARGUMENT;
    }
    let bytes = if name_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(name, name_len)
    };
    // Package names come from the platform (`PackageManager`), so this is lossy only for a caller
    // bug; lossy keeps the row instead of turning it into an error.
    let name = String::from_utf8_lossy(bytes);
    (*handle).store(uid, &name, now_ns);
    STATUS_OK
}

/// Current package entry count.
///
/// # Safety
///
/// The handle must be valid for the call.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_package_len(handle: *const UidPackageCache) -> u32 {
    handle.as_ref().map_or(0, UidPackageCache::len)
}

// --- shared -----------------------------------------------------------------------------------

/// Drops a payload a `drain` / `tick` call returned.
///
/// # Safety
///
/// `pointer` / `length` must be exactly what a call returned, and must not be freed twice.
#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

/// Hands an encoded payload to the caller, as a boxed slice Go frees with its length.
unsafe fn emit(encoded: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let mut boxed = encoded.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

#[cfg(test)]
mod tests;
