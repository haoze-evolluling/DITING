//! The C ABI `android/engine/resolver_stats_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_resolver_abi_version` | ABI number the loader validates |
//! | `diting_resolver_new` | build one provider's statistics |
//! | `diting_resolver_free` | drop a handle |
//! | `diting_resolver_record_success` | fold one RTT sample in, clear the failure streak |
//! | `diting_resolver_record_failure` | count `weight` failed attempts |
//! | `diting_resolver_record_policy_failure` | count a policy rejection (trips the circuit) |
//! | `diting_resolver_allow_attempt` | circuit-breaker decision, may arm the half-open probe |
//! | `diting_resolver_record_censored` | record a loser's elapsed time as a lower-bound sample |
//! | `diting_resolver_score` | expected cost at `now_ns`, for the provider ranking |
//! | `diting_resolver_hedge_delay` | `smart_prediction` stagger before the next candidate |
//! | `diting_resolver_attempt_timeout` | per-attempt timeout of sequential failover |
//! | `diting_resolver_udp_retry_delay` | plain-UDP retry interval on the same upstream |
//! | `diting_resolver_sample_count` | RTT samples folded in so far |
//! | `diting_resolver_failure_count` | consecutive failures since the last success |
//! | `diting_resolver_sched_new` | one query's scheduling session (`resolveConfigured`) |
//! | `diting_resolver_sched_free` | drop a session handle |
//! | `diting_resolver_sched_start` | the first attempt(s) of the query |
//! | `diting_resolver_sched_launched` | confirm or reject one launch request |
//! | `diting_resolver_sched_result` | one attempt's outcome, with the next actions |
//! | `diting_resolver_sched_hedge` | the `smart_prediction` hedge timer fired |
//! | `diting_resolver_sched_grace` | the encrypted grace window expired |
//! | `diting_resolver_free_bytes` | drop a payload this library returned |
//!
//! Every duration and timestamp is nanoseconds: Go converts `time.Duration` / `time.Time` on its
//! side and the kernel never reads a clock. A null handle makes the recording calls and the
//! decisions no-ops and the getters report the cold values, exactly like the other kernels.

use std::slice;

use crate::payload::{decode_plan, encode_step};
use crate::schedule::{Schedule, Step};
use crate::stats::{
    ProviderStats, ATTEMPT_TIMEOUT_COLD_NS, DEFAULT_EWMA_NS, HEDGE_DELAY_COLD_NS,
    UDP_RETRY_DELAY_COLD_NS,
};

/// Must match `resolverStatsABIVersion` in `android/engine/resolver_stats_native.go`.
pub const ABI_VERSION: u32 = 2;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_resolver_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates the statistics of one provider: no samples, no failures, closed circuit.
#[no_mangle]
pub extern "C" fn diting_resolver_new() -> *mut ProviderStats {
    Box::into_raw(Box::new(ProviderStats::new()))
}

/// Drops a handle created by [`diting_resolver_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_resolver_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_free(handle: *mut ProviderStats) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Folds one RTT sample in and clears the failure streak and the circuit.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
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

/// Counts `weight` consecutive failed attempts (clamped to at least one).
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
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

/// Counts a policy/configuration rejection (REFUSED, FORMERR, NOTIMP): weight 3, so it trips the
/// circuit breaker immediately.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
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

/// Reports whether the provider may be tried at `now_ns`; arms the half-open probe when the
/// cooldown has expired.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
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

/// Records a query that was cancelled because another provider answered first.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
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

/// Expected cost of using the provider at `now_ns`.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_score(handle: *const ProviderStats, now_ns: i64) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.score(now_ns),
        None => DEFAULT_EWMA_NS,
    }
}

/// Hedge delay of `smart_prediction` for this provider.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_hedge_delay(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.hedge_delay(),
        None => HEDGE_DELAY_COLD_NS,
    }
}

/// Per-attempt timeout of `primary_backup` for this provider.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_attempt_timeout(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.attempt_timeout(),
        None => ATTEMPT_TIMEOUT_COLD_NS,
    }
}

/// Plain-UDP retry interval for this provider.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_udp_retry_delay(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.udp_retry_delay(),
        None => UDP_RETRY_DELAY_COLD_NS,
    }
}

/// RTT samples folded into this provider so far.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sample_count(handle: *const ProviderStats) -> i64 {
    match handle.as_ref() {
        Some(stats) => stats.sample_count(),
        None => 0,
    }
}

/// Consecutive failures since the last success.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_failure_count(handle: *const ProviderStats) -> u32 {
    match handle.as_ref() {
        Some(stats) => stats.failure_count(),
        None => 0,
    }
}

// --- scheduling sessions ---------------------------------------------------------------------

/// Creates one query's scheduling session from a plan payload.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes.
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

/// Drops a session created by [`diting_resolver_sched_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_resolver_sched_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_sched_free(handle: *mut Schedule) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Starts the query.
///
/// # Safety
///
/// `out` / `out_len` must be writable and the handle must be valid for the call.
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

/// Confirms (or rejects) one launch request.
///
/// # Safety
///
/// `out` / `out_len` must be writable and the handle must be valid for the call.
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

/// Reports one attempt's outcome; `error` may be null when the attempt succeeded.
///
/// # Safety
///
/// `error` must be readable for `error_len` bytes when non-null, and `out` / `out_len` writable.
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

/// The `smart_prediction` hedge timer fired.
///
/// # Safety
///
/// `out` / `out_len` must be writable and the handle must be valid for the call.
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

/// The encrypted grace window expired.
///
/// # Safety
///
/// `out` / `out_len` must be writable and the handle must be valid for the call.
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

/// Drops a payload this library returned.
///
/// # Safety
///
/// `pointer` must come from [`emit`] and `length` must be its length.
#[no_mangle]
pub unsafe extern "C" fn diting_resolver_free_bytes(pointer: *mut u8, length: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

/// Hands an encoded step to the caller, as a boxed slice Go frees with its length.
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
