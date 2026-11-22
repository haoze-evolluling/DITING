use std::slice;

use crate::hosts::HostsTable;
use crate::ip::Addr;
use crate::payload::{encode_arpa_name, encode_info, encode_lookup, encode_names, encode_reverse};

pub const ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_hosts_abi_version() -> u32 {
    ABI_VERSION
}

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

#[no_mangle]
pub unsafe extern "C" fn diting_hosts_free(handle: *mut HostsTable) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_hosts_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

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
