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
//!
//! Every duration and timestamp is nanoseconds: Go converts `time.Duration` / `time.Time` on its
//! side and the kernel never reads a clock. A null handle makes the recording calls and the
//! decisions no-ops and the getters report the cold values, exactly like the other kernels.

use crate::stats::{
    ProviderStats, ATTEMPT_TIMEOUT_COLD_NS, DEFAULT_EWMA_NS, HEDGE_DELAY_COLD_NS,
    UDP_RETRY_DELAY_COLD_NS,
};

/// Must match `resolverStatsABIVersion` in `android/engine/resolver_stats_native.go`.
pub const ABI_VERSION: u32 = 1;

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

#[cfg(test)]
mod tests;
