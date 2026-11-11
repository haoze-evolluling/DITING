//! The C ABI `desktop/service/internal/core/hosts_native.go` loads with pure Go dlopen.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_hosts_abi_version` | ABI number the loader validates |
//! | `diting_hosts_new` | read the sources and build a table |
//! | `diting_hosts_info` | loaded paths + the last read error |
//! | `diting_hosts_free` | drop a table |
//! | `diting_hosts_free_bytes` | drop a payload this library returned |
//! | `diting_hosts_lookup` | A / AAAA answer for one host |
//! | `diting_hosts_contains` | does any map hold this host (`HasDomain`) |
//! | `diting_hosts_ptr` | reverse name -> every alias |
//! | `diting_hosts_reverse` | address -> the first alias |
//! | `diting_hosts_parse_arpa` | reverse name -> address (`ParseIPFromArpa`) |
//!
//! A null handle makes every read a miss, exactly like the other kernels: a Go caller that already
//! decided to answer from hosts without a handle has nothing to answer with, so "not found" is the
//! honest answer rather than a panic inside a resolver goroutine.
//!
//! Every function returns `1` on success and `0` on a bad argument (null handle, invalid UTF-8, a
//! payload that does not decode). `diting_hosts_contains` returns the boolean itself: `1` for "in
//! the table", `0` for "not" and for a bad argument — the Go side only ever asks with a live
//! handle, so the two cases cannot be confused by a caller that has one.

use std::slice;

use crate::hosts::HostsTable;
use crate::ip::Addr;
use crate::payload::{encode_arpa_name, encode_info, encode_lookup, encode_names, encode_reverse};

/// Must match `hostsNativeABIVersion` in `desktop/service/internal/core/hosts_native.go`.
pub const ABI_VERSION: u32 = 1;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_hosts_abi_version() -> u32 {
    ABI_VERSION
}

/// Builds a table from the encoded source list, writing the handle to `out`.
///
/// The table is immutable once built: `UpdateConfig` / `Reload` in Go build a new one and swap the
/// pointer, which is what the Go side did with the maps before the move.
///
/// # Safety
///
/// `sources` must be readable for `sources_len` bytes and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_new(
    sources: *const u8,
    sources_len: usize,
    out: *mut *mut HostsTable,
) -> u32 {
    if out.is_null() {
        return 0;
    }
    let Some(data) = slice_from(sources, sources_len) else {
        return 0;
    };
    let Ok(decoded) = crate::payload::decode_sources(data) else {
        return 0;
    };
    *out = Box::into_raw(Box::new(HostsTable::build(&decoded)));
    1
}

/// Drops a table created by [`diting_hosts_new`].
///
/// # Safety
///
/// `handle` must come from [`diting_hosts_new`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_free(handle: *mut HostsTable) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Frees a payload returned by this library.
///
/// # Safety
///
/// `pointer`/`length` must be a pair this library produced and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Writes the loaded paths and the last read error.
///
/// # Safety
///
/// `out_ptr`/`out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_info(
    handle: *const HostsTable,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(table) = handle.as_ref() else {
        return 0;
    };
    write_payload(encode_info(table.loaded(), table.error()), out_ptr, out_len)
}

/// Answers one qtype for `host`; an empty answer is a payload with zero addresses.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes and `out_ptr`/`out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_lookup(
    handle: *const HostsTable,
    host: *const u8,
    host_len: usize,
    qtype: u16,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(table) = handle.as_ref() else {
        return 0;
    };
    let Some(host) = text(host, host_len) else {
        return 0;
    };
    write_payload(encode_lookup(&table.lookup(host, qtype)), out_ptr, out_len)
}

/// `HasDomain`: `1` when the table holds the host, `0` otherwise.
///
/// # Safety
///
/// `host` must be readable for `host_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_contains(
    handle: *const HostsTable,
    host: *const u8,
    host_len: usize,
) -> u32 {
    let Some(table) = handle.as_ref() else {
        return 0;
    };
    let Some(host) = text(host, host_len) else {
        return 0;
    };
    u32::from(table.has_domain(host))
}

/// Resolves a reverse name to every alias, in file order.
///
/// # Safety
///
/// `arpa` must be readable for `arpa_len` bytes and `out_ptr`/`out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_ptr(
    handle: *const HostsTable,
    arpa: *const u8,
    arpa_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(table) = handle.as_ref() else {
        return 0;
    };
    let Some(arpa) = text(arpa, arpa_len) else {
        return 0;
    };
    write_payload(encode_names(&table.ptr(arpa)), out_ptr, out_len)
}

/// Resolves an address (4 or 16 bytes) to the first name registered for it.
///
/// # Safety
///
/// `address` must be readable for `address_len` bytes and `out_ptr`/`out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_reverse(
    handle: *const HostsTable,
    address: *const u8,
    address_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(table) = handle.as_ref() else {
        return 0;
    };
    let Some(bytes) = slice_from(address, address_len) else {
        return 0;
    };
    let Some(address) = Addr::from_bytes(bytes) else {
        return 0;
    };
    write_payload(encode_reverse(table.reverse(&address)), out_ptr, out_len)
}

/// `ParseIPFromArpa`: a reverse name to an address, or `width = 0`. Needs no table.
///
/// # Safety
///
/// `name` must be readable for `name_len` bytes and `out_ptr`/`out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_hosts_parse_arpa(
    name: *const u8,
    name_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    let Some(name) = text(name, name_len) else {
        return 0;
    };
    write_payload(encode_arpa_name(name), out_ptr, out_len)
}

unsafe fn write_payload(payload: Vec<u8>, out_ptr: *mut *mut u8, out_len: *mut usize) -> u32 {
    if !out_ptr.is_null() {
        *out_ptr = std::ptr::null_mut();
    }
    if !out_len.is_null() {
        *out_len = 0;
    }
    let length = payload.len();
    let boxed = payload.into_boxed_slice();
    if !out_ptr.is_null() {
        *out_ptr = Box::into_raw(boxed) as *mut u8;
    }
    if !out_len.is_null() {
        *out_len = length;
    }
    1
}

/// Reads a UTF-8 text argument; `None` when it is not valid UTF-8.
unsafe fn text<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    let bytes = slice_from(pointer, length)?;
    std::str::from_utf8(bytes).ok()
}

unsafe fn slice_from<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
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
