//! The C ABI `android/engine/bootstrap_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_bootstrap_abi_version` | ABI number the loader validates |
//! | `diting_bootstrap_new` | one resolver's kernel state |
//! | `diting_bootstrap_free` | drop a handle |
//! | `diting_bootstrap_reset` | clear health history and host cache (`ResetStats`) |
//! | `diting_bootstrap_clear_cache` | clear only the host cache (`UpdateConfig`) |
//! | `diting_bootstrap_record_result` | fold one bootstrap attempt into an endpoint's health |
//! | `diting_bootstrap_score` | the endpoint's current weight, cooldown flag and sample count |
//! | `diting_bootstrap_plan` | primary + fallback order for one resolution |
//! | `diting_bootstrap_cache_get` | the cached address of a host, if still fresh |
//! | `diting_bootstrap_cache_put` | cache one address for a minute |
//! | `diting_bootstrap_health_count` | number of endpoints with a health entry (tests) |
//!
//! Every timestamp is unix nanoseconds and comes from Go; the kernel never reads a clock. The
//! random rolls are also injected. A null handle turns the mutators into no-ops and the queries
//! into misses / `-1`, so the loader can treat "kernel absent" as "bootstrap disabled".

use std::ptr;
use std::slice;
use std::str;

use crate::engine::BootstrapKernel;
use crate::payload::{decode_plan_entries, encode_plan, encode_score};

/// Must match `bootstrapABIVersion` in `android/engine/bootstrap_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

const RESULT_BAD_ARGUMENT: isize = -1;
const RESULT_BAD_PAYLOAD: isize = -2;
const RESULT_TOO_SMALL: isize = -3;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_bootstrap_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates the kernel state of one bootstrap resolver.
#[no_mangle]
pub extern "C" fn diting_bootstrap_new() -> *mut BootstrapKernel {
    Box::into_raw(Box::new(BootstrapKernel::new()))
}

/// Drops a handle created by [`diting_bootstrap_new`].
///
/// # Safety
///
/// `handle` must come from `diting_bootstrap_new` and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_free(handle: *mut BootstrapKernel) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// `ResetStats`: forget every health entry and cached address.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_reset(handle: *const BootstrapKernel) -> u32 {
    match handle.as_ref() {
        Some(kernel) => {
            kernel.reset();
            STATUS_OK
        }
        None => STATUS_BAD_ARGUMENT,
    }
}

/// `UpdateConfig`'s cache invalidation; health history is kept.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_clear_cache(handle: *const BootstrapKernel) -> u32 {
    match handle.as_ref() {
        Some(kernel) => {
            kernel.clear_cache();
            STATUS_OK
        }
        None => STATUS_BAD_ARGUMENT,
    }
}

/// `RecordResult` for the endpoint `id`.
///
/// # Safety
///
/// `id` must be readable for `id_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_record_result(
    handle: *const BootstrapKernel,
    id: *const u8,
    id_len: usize,
    success: u32,
    elapsed_ms: i64,
    now_ns: i64,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return STATUS_BAD_ARGUMENT;
    };
    let id = match text_argument(id, id_len) {
        Some(id) => id,
        None => return STATUS_BAD_PAYLOAD,
    };
    kernel.record_result(id, success != 0, elapsed_ms, now_ns);
    STATUS_OK
}

/// Reads a text argument. A zero length is the empty string (a JSON config may omit the endpoint
/// id, and the old Go health map keyed those under `""`); a null pointer with a non-zero length is
/// a caller bug.
unsafe fn text_argument<'a>(text: *const u8, len: usize) -> Option<&'a str> {
    if len == 0 {
        return Some("");
    }
    if text.is_null() {
        return None;
    }
    str::from_utf8(slice::from_raw_parts(text, len)).ok()
}

/// `GetScore` for the endpoint `id`; writes `f64 weight | u8 cooling | f64 sample_count`.
///
/// # Safety
///
/// `id` must be readable for `id_len` bytes and `out` writable for `out_cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_score(
    handle: *const BootstrapKernel,
    id: *const u8,
    id_len: usize,
    entry_weight: f64,
    now_ns: i64,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let Some(kernel) = handle.as_ref() else {
        return RESULT_BAD_ARGUMENT;
    };
    if out.is_null() {
        return RESULT_BAD_ARGUMENT;
    }
    let Some(id) = text_argument(id, id_len) else {
        return RESULT_BAD_PAYLOAD;
    };
    let score = kernel.score(id, entry_weight, now_ns);
    let encoded = encode_score(score.weight, score.cooling_down, score.sample_count);
    copy_out(&encoded, out, out_cap)
}

/// `choosePlan`: entries payload in, plan payload out.
///
/// # Safety
///
/// `entries` must be readable for `entries_len` bytes and `out` writable for `out_cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_plan(
    handle: *const BootstrapKernel,
    now_ns: i64,
    explore_roll: f64,
    weight_roll: f64,
    index_roll: u64,
    entries: *const u8,
    entries_len: usize,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let Some(kernel) = handle.as_ref() else {
        return RESULT_BAD_ARGUMENT;
    };
    if entries.is_null() || out.is_null() {
        return RESULT_BAD_ARGUMENT;
    }
    let Some(entries) = decode_plan_entries(slice::from_raw_parts(entries, entries_len)) else {
        return RESULT_BAD_PAYLOAD;
    };
    let plan = kernel.plan(&entries, now_ns, explore_roll, weight_roll, index_roll);
    copy_out(&encode_plan(&plan), out, out_cap)
}

/// `getCached`: writes the address bytes and returns their length, or `-1` on a miss.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes and `out` writable for `out_cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_cache_get(
    handle: *const BootstrapKernel,
    host: *const u8,
    host_len: usize,
    now_ns: i64,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let Some(kernel) = handle.as_ref() else {
        return RESULT_BAD_ARGUMENT;
    };
    if host.is_null() || host_len == 0 || out.is_null() {
        return RESULT_BAD_ARGUMENT;
    }
    let Ok(host) = str::from_utf8(slice::from_raw_parts(host, host_len)) else {
        return RESULT_BAD_PAYLOAD;
    };
    match kernel.cache_get(host, now_ns) {
        Some(ip) => copy_out(ip.as_bytes(), out, out_cap),
        None => RESULT_BAD_ARGUMENT,
    }
}

/// `putCached`: one address for one minute.
///
/// # Safety
///
/// Both slices must be readable for their stated lengths.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_cache_put(
    handle: *const BootstrapKernel,
    host: *const u8,
    host_len: usize,
    ip: *const u8,
    ip_len: usize,
    now_ns: i64,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return STATUS_BAD_ARGUMENT;
    };
    if host.is_null() || host_len == 0 || ip.is_null() || ip_len == 0 {
        return STATUS_BAD_ARGUMENT;
    }
    let (Ok(host), Ok(ip)) = (
        str::from_utf8(slice::from_raw_parts(host, host_len)),
        str::from_utf8(slice::from_raw_parts(ip, ip_len)),
    ) else {
        return STATUS_BAD_PAYLOAD;
    };
    kernel.cache_put(host, ip, now_ns);
    STATUS_OK
}

/// Number of endpoints with a health entry (the old test's `len(healthMap)`).
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_bootstrap_health_count(handle: *const BootstrapKernel) -> u32 {
    match handle.as_ref() {
        Some(kernel) => kernel.health_count(),
        None => 0,
    }
}

/// Copies `bytes` into the caller's buffer. `SCORE_BYTES` is the only fixed-size case; the plan
/// and address responses are copied the same way.
unsafe fn copy_out(bytes: &[u8], out: *mut u8, out_cap: usize) -> isize {
    if out_cap < bytes.len() {
        return RESULT_TOO_SMALL;
    }
    ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len());
    bytes.len() as isize
}

#[cfg(test)]
mod tests;
