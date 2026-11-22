use std::slice;

use crate::admit::{admit, FlowInput};
use crate::blocked::BlockedUids;
use crate::route::{per_app, proxies_uid, resolver_uses_proxy};

pub const ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_gate_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn diting_gate_blocked_new(
    csv: *const u8,
    csv_len: usize,
) -> *mut BlockedUids {
    let Some(csv) = text(csv, csv_len) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(BlockedUids::parse_csv(csv)))
}

#[no_mangle]
pub unsafe extern "C" fn diting_gate_blocked_is_blocked(
    handle: *const BlockedUids,
    uid: i64,
) -> u32 {
    let Some(set) = handle.as_ref() else {
        return 0;
    };
    u32::from(set.is_blocked(uid))
}

#[no_mangle]
pub unsafe extern "C" fn diting_gate_blocked_free(handle: *mut BlockedUids) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_gate_per_app(
    enabled: u32,
    scope: *const u8,
    scope_len: usize,
) -> u32 {
    let Some(scope) = text(scope, scope_len) else {
        return 0;
    };
    u32::from(per_app(enabled != 0, scope))
}

#[no_mangle]
pub unsafe extern "C" fn diting_gate_proxies_uid(
    enabled: u32,
    scope: *const u8,
    scope_len: usize,
    uid: i64,
    uids: *const i64,
    uids_len: usize,
) -> u32 {
    let Some(scope) = text(scope, scope_len) else {
        return 0;
    };
    let Some(uids) = ints(uids, uids_len) else {
        return 0;
    };
    u32::from(proxies_uid(enabled != 0, scope, uid, uids))
}

#[no_mangle]
pub unsafe extern "C" fn diting_gate_resolver_uses_proxy(
    enabled: u32,
    scope: *const u8,
    scope_len: usize,
) -> u32 {
    let Some(scope) = text(scope, scope_len) else {
        return 0;
    };
    u32::from(resolver_uses_proxy(enabled != 0, scope))
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn diting_gate_admit(
    mode: u32,
    port: u32,
    ip: *const u8,
    ip_len: usize,
    uid_blocked: u32,
    app_allowlist_allowed: u32,
    encrypted_dns_blocked: u32,
    quic_drop: u32,
    quic_uid_selected: u32,
    mitm_uid_allowed: u32,
) -> u32 {
    let Some(ip) = bytes(ip, ip_len) else {
        return crate::admit::Decision::new(crate::admit::ACTION_BLOCK_UID, false).to_u32();
    };
    let input = FlowInput {
        uid_blocked: uid_blocked != 0,
        app_allowlist_allowed: app_allowlist_allowed != 0,
        encrypted_dns_blocked: encrypted_dns_blocked != 0,
        quic_drop: quic_drop != 0,
        quic_uid_selected: quic_uid_selected != 0,
        mitm_uid_allowed: mitm_uid_allowed != 0,
        port: port as u16,
        ip,
    };
    admit(mode as u8, &input).to_u32()
}

unsafe fn text<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    if length == 0 {
        return Some("");
    }
    if pointer.is_null() {
        return None;
    }
    std::str::from_utf8(slice::from_raw_parts(pointer, length)).ok()
}

unsafe fn bytes<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if length == 0 {
        return Some(&[]);
    }
    if pointer.is_null() {
        return None;
    }
    Some(slice::from_raw_parts(pointer, length))
}

unsafe fn ints<'a>(pointer: *const i64, length: usize) -> Option<&'a [i64]> {
    if length == 0 {
        return Some(&[]);
    }
    if pointer.is_null() {
        return None;
    }
    Some(slice::from_raw_parts(pointer, length))
}

#[cfg(test)]
mod tests;
