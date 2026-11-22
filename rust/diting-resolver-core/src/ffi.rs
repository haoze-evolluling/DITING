use std::slice;

use crate::payload::{decode_plan, encode_step};
use crate::schedule::{Schedule, Step};
use crate::stats::{
    ProviderStats, ATTEMPT_TIMEOUT_COLD_NS, DEFAULT_EWMA_NS, HEDGE_DELAY_COLD_NS,
    UDP_RETRY_DELAY_COLD_NS,
};

pub const ABI_VERSION: u32 = 2;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_resolver_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn diting_resolver_new() -> *mut ProviderStats {
    Box::into_raw(Box::new(ProviderStats::new()))
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_free(handle: *mut ProviderStats) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_record_success(
    handle: *const ProviderStats,
    rtt_ns: i64,
    now_ns: i64,
) -> u32 {
    match handle.as_ref() {
        Some(stats) => {
            stats.record_success(rtt_ns, now_ns);
            1
        }
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_record_failure(
    handle: *const ProviderStats,
    weight: u32,
    now_ns: i64,
) -> u32 {
    match handle.as_ref() {
        Some(stats) => {
            stats.record_failure_weight(weight, now_ns);
            1
        }
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_record_policy_failure(
    handle: *const ProviderStats,
    now_ns: i64,
) -> u32 {
    match handle.as_ref() {
        Some(stats) => {
            stats.record_policy_failure(now_ns);
            1
        }
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_allow_attempt(
    handle: *const ProviderStats,
    now_ns: i64,
) -> u32 {
    match handle.as_ref() {
        Some(stats) if stats.allow_attempt(now_ns) => 1,
        Some(_) => 0,
        None => 1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_record_censored(
    handle: *const ProviderStats,
    elapsed_ns: i64,
) -> u32 {
    match handle.as_ref() {
        Some(stats) => {
            stats.record_censored(elapsed_ns);
            1
        }
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_score(handle: *const ProviderStats, now_ns: i64) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.score(now_ns),
        None => DEFAULT_EWMA_NS,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_hedge_delay(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.hedge_delay(),
        None => HEDGE_DELAY_COLD_NS,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_attempt_timeout(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.attempt_timeout(),
        None => ATTEMPT_TIMEOUT_COLD_NS,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_udp_retry_delay(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.udp_retry_delay(),
        None => UDP_RETRY_DELAY_COLD_NS,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sample_count(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.sample_count(),
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_failure_count(handle: *const ProviderStats) -> u32 {
    match handle.as_ref() {
        Some(stats) => stats.failure_count(),
        None => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_new(
    payload: *const u8,
    payload_len: usize,
) -> *mut Schedule {
    if payload.is_null() {
        return std::ptr::null_mut();
    }
    let Some(input) = decode_plan(slice::from_raw_parts(payload, payload_len)) else {
        return std::ptr::null_mut();
    };
    match Schedule::new(input) {
        Some(schedule) => Box::into_raw(Box::new(schedule)),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_free(handle: *mut Schedule) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_start(
    handle: *const Schedule,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(schedule) = handle.cast_mut().as_mut() else {
        return STATUS_BAD_ARGUMENT;
    };
    emit(schedule.start(), out, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_launched(
    handle: *const Schedule,
    provider: u32,
    launched: u32,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(schedule) = handle.cast_mut().as_mut() else {
        return STATUS_BAD_ARGUMENT;
    };
    emit(schedule.launched(provider, launched != 0), out, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_result(
    handle: *const Schedule,
    provider: u32,
    ok: u32,
    elapsed_ns: i64,
    since_start_ns: i64,
    parent_cancelled: u32,
    error: *const u8,
    error_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(schedule) = handle.cast_mut().as_mut() else {
        return STATUS_BAD_ARGUMENT;
    };
    let text = if error.is_null() {
        None
    } else {
        Some(String::from_utf8_lossy(slice::from_raw_parts(error, error_len)).into_owned())
    };
    emit(
        schedule.result(
            provider,
            ok != 0,
            elapsed_ns,
            since_start_ns,
            parent_cancelled != 0,
            text.as_deref(),
        ),
        out,
        out_len,
    )
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_hedge(
    handle: *const Schedule,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(schedule) = handle.cast_mut().as_mut() else {
        return STATUS_BAD_ARGUMENT;
    };
    emit(schedule.hedge(), out, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_grace(
    handle: *const Schedule,
    since_start_ns: i64,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(schedule) = handle.cast_mut().as_mut() else {
        return STATUS_BAD_ARGUMENT;
    };
    emit(schedule.grace(since_start_ns), out, out_len)
}

#[no_mangle]
pub unsafe extern "C" fn diting_resolver_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

unsafe fn emit(step: Step, out: *mut *mut u8, out_len: *mut usize) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let mut boxed = encode_step(&step).into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out = pointer;
    *out_len = length;
    STATUS_OK
}

#[cfg(test)]
mod tests;
