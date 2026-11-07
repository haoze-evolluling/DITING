//! The C ABI `android/engine/allowlist_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_allowlist_abi_version` | ABI number the loader validates |
//! | `diting_allowlist_new` | one engine's allowlist state |
//! | `diting_allowlist_free` | drop a handle |
//! | `diting_allowlist_configure` | replace the domain sets and drop every grant (`SetAppAllowlist`) |
//! | `diting_allowlist_has_uids` | any UID is under strict mode |
//! | `diting_allowlist_domain_allowed` | may this UID resolve this domain? |
//! | `diting_allowlist_connection_allowed` | does this UID hold a live grant for this address? |
//! | `diting_allowlist_remember` | grant one answer's A/AAAA records to the matching UIDs |
//! | `diting_allowlist_grant_count` | number of stored grants of a UID (tests) |
//!
//! Every timestamp is unix nanoseconds and comes from Go; the kernel never reads a clock. A null
//! handle allows lookups (no rules) and turns the mutators into no-ops.

use std::slice;
use std::str;

use crate::engine::AllowlistKernel;
use crate::payload::{decode_configure, decode_remember};

/// Must match `allowlistABIVersion` in `android/engine/allowlist_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_allowlist_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates the allowlist state of one engine.
#[no_mangle]
pub extern "C" fn diting_allowlist_new() -> *mut AllowlistKernel {
    Box::into_raw(Box::new(AllowlistKernel::new()))
}

/// Drops a handle created by [`diting_allowlist_new`].
///
/// # Safety
///
/// `handle` must come from `diting_allowlist_new` and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_free(handle: *mut AllowlistKernel) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// `SetAppAllowlist`'s state replacement.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_configure(
    handle: *const AllowlistKernel,
    payload: *const u8,
    payload_len: usize,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return STATUS_OK;
    };
    if payload.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(entries) = decode_configure(slice::from_raw_parts(payload, payload_len)) else {
        return STATUS_BAD_PAYLOAD;
    };
    kernel.configure(&entries);
    STATUS_OK
}

/// `hasAppAllowlistUIDs`.
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_has_uids(handle: *const AllowlistKernel) -> u32 {
    match handle.as_ref() {
        Some(kernel) => u32::from(kernel.has_uids()),
        None => 0,
    }
}

/// `appAllowlistDomainAllowed`.
///
/// # Safety
///
/// `domain` must be readable for `domain_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_domain_allowed(
    handle: *const AllowlistKernel,
    uid: i32,
    domain: *const u8,
    domain_len: usize,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return 1;
    };
    let Some(domain) = text_argument(domain, domain_len) else {
        return 0;
    };
    u32::from(kernel.domain_allowed(uid, domain))
}

/// `appAllowlistConnectionAllowed`.
///
/// # Safety
///
/// `address` must be readable for `address_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_connection_allowed(
    handle: *const AllowlistKernel,
    uid: i32,
    address: *const u8,
    address_len: usize,
    now_ns: i64,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return 1;
    };
    let address = if address_len == 0 {
        &[][..]
    } else if address.is_null() {
        return 0;
    } else {
        slice::from_raw_parts(address, address_len)
    };
    u32::from(kernel.connection_allowed(uid, address, now_ns))
}

/// `rememberAppAllowlistResponse`.
///
/// # Safety
///
/// `payload` must be readable for `payload_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_remember(
    handle: *const AllowlistKernel,
    payload: *const u8,
    payload_len: usize,
    now_ns: i64,
) -> u32 {
    let Some(kernel) = handle.as_ref() else {
        return STATUS_OK;
    };
    if payload.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(request) = decode_remember(slice::from_raw_parts(payload, payload_len)) else {
        return STATUS_BAD_PAYLOAD;
    };
    kernel.remember(
        request.uid,
        &request.question_name,
        &request.records,
        now_ns,
    );
    STATUS_OK
}

/// Number of stored grants for a UID (the old test's `len(ips[uid])`).
///
/// # Safety
///
/// The handle must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn diting_allowlist_grant_count(
    handle: *const AllowlistKernel,
    uid: i32,
) -> u32 {
    match handle.as_ref() {
        Some(kernel) => kernel.grant_count(uid),
        None => 0,
    }
}

/// Reads a text argument. A zero length is the empty string; a null pointer with a non-zero length
/// is a caller bug.
unsafe fn text_argument<'a>(text: *const u8, len: usize) -> Option<&'a str> {
    if len == 0 {
        return Some("");
    }
    if text.is_null() {
        return None;
    }
    str::from_utf8(slice::from_raw_parts(text, len)).ok()
}

#[cfg(test)]
mod tests;
