use std::slice;

use crate::logagg::{LogAggregator, PushOutcome};
use crate::payload::{
    decode_flow_lookup, decode_flow_store, decode_log_push, encode_log_batch, encode_traffic_tick,
};
use crate::traffic::TrafficTracker;
use crate::uidcache::{FlowUidCache, UidPackageCache};

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

#[no_mangle]
pub extern "C" fn diting_telemetry_abi_version() -> u32 {
    ABI_VERSION
}


#[no_mangle]
pub extern "C" fn diting_telemetry_log_new() -> *mut LogAggregator {
    Box::into_raw(Box::new(LogAggregator::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_free(handle: *mut LogAggregator) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_pending(handle: *const LogAggregator) -> u32 {
    handle
        .as_ref()
        .map_or(0, |aggregator| aggregator.pending() as u32)
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_dropped(handle: *const LogAggregator) -> u64 {
    handle.as_ref().map_or(0, LogAggregator::dropped)
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_log_dropped_conn(handle: *const LogAggregator) -> u64 {
    handle.as_ref().map_or(0, LogAggregator::dropped_conn)
}


#[no_mangle]
pub extern "C" fn diting_telemetry_traffic_new() -> *mut TrafficTracker {
    Box::into_raw(Box::new(TrafficTracker::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_free(handle: *mut TrafficTracker) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_interval_ms(
    handle: *const TrafficTracker,
) -> i64 {
    handle.as_ref().map_or(0, TrafficTracker::interval_ms)
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_traffic_unique_uids(
    handle: *const TrafficTracker,
) -> u32 {
    handle.as_ref().map_or(0, TrafficTracker::unique_uids)
}

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


#[no_mangle]
pub extern "C" fn diting_telemetry_flow_new() -> *mut FlowUidCache {
    Box::into_raw(Box::new(FlowUidCache::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_flow_free(handle: *mut FlowUidCache) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_flow_len(handle: *const FlowUidCache) -> u32 {
    handle.as_ref().map_or(0, FlowUidCache::len)
}


#[no_mangle]
pub extern "C" fn diting_telemetry_package_new() -> *mut UidPackageCache {
    Box::into_raw(Box::new(UidPackageCache::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_package_free(handle: *mut UidPackageCache) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

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
    let name = String::from_utf8_lossy(bytes);
    (*handle).store(uid, &name, now_ns);
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_package_len(handle: *const UidPackageCache) -> u32 {
    handle.as_ref().map_or(0, UidPackageCache::len)
}


#[no_mangle]
pub unsafe extern "C" fn diting_telemetry_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

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
