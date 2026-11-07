//! The C ABI `android/engine/cert_native.go` loads with `dlopen`.
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_cert_abi_version` | ABI number the loader validates |
//! | `diting_cert_generate` | mint a new root CA, return the handle + its key PEM |
//! | `diting_cert_load` | validate and adopt a persisted root |
//! | `diting_cert_ca_pem` | the CA certificate PEM |
//! | `diting_cert_issue` | one leaf certificate for a host |
//! | `diting_cert_is_ev` | is a certificate's policy list EV |
//! | `diting_cert_free` | drop a handle and its keys |
//! | `diting_cert_free_bytes` | drop a payload this library returned |
//!
//! Every response payload is a sequence of `str` fields (`u32 little-endian length | UTF-8 bytes`):
//!
//! * generate: `str ca_cert_pem | str ca_key_pem`;
//! * load: empty;
//! * ca_pem: `str ca_cert_pem`;
//! * issue: `str leaf_chain_pem | str leaf_key_pem | i64 not_after_unix`;
//! * any operation error (status `3`): `str message`.
//!
//! Status codes are `0` ok, `1` bad argument, `2` bad payload (non-UTF-8 text), `3` operation
//! error. Every entry point catches a panic: unwinding out of an `extern "C"` function aborts the
//! process, and a crypto library assert must not take the tunnel down.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;

use crate::ca::{CertAuthority, GeneratedCa, IssuedLeaf};
use crate::ev::is_extended_validation_csv;

/// Must match `certABIVersion` in `android/engine/cert_native.go`.
pub const ABI_VERSION: u32 = 1;

const STATUS_OK: u32 = 0;
const STATUS_BAD_ARGUMENT: u32 = 1;
const STATUS_BAD_PAYLOAD: u32 = 2;
const STATUS_OPERATION: u32 = 3;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_cert_abi_version() -> u32 {
    ABI_VERSION
}

/// Mints a new root CA and hands back its handle.
///
/// # Safety
///
/// `handle_out`, `out` and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_cert_generate(
    now_unix: i64,
    handle_out: *mut *mut CertAuthority,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if handle_out.is_null() || out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let result = catch_unwind(AssertUnwindSafe(|| CertAuthority::generate(now_unix)));
    match result {
        Ok(Ok(GeneratedCa {
            authority,
            ca_key_pem,
        })) => {
            let payload = {
                let mut writer = PayloadWriter::new();
                writer.text(authority.ca_pem());
                writer.text(&ca_key_pem);
                writer.finish()
            };
            *handle_out = Box::into_raw(Box::new(authority));
            write_payload(payload, out, out_len);
            STATUS_OK
        }
        Ok(Err(message)) => {
            write_error(&message, out, out_len);
            STATUS_OPERATION
        }
        Err(_) => {
            write_error("certificate generation panicked", out, out_len);
            STATUS_OPERATION
        }
    }
}

/// Validates and adopts a persisted root CA.
///
/// # Safety
///
/// The text arguments must be readable for their lengths; the out pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_cert_load(
    cert: *const u8,
    cert_len: usize,
    key: *const u8,
    key_len: usize,
    now_unix: i64,
    handle_out: *mut *mut CertAuthority,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if handle_out.is_null() || out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let (Some(cert), Some(key)) = (text(cert, cert_len), text(key, key_len)) else {
        return STATUS_BAD_PAYLOAD;
    };
    match catch_unwind(AssertUnwindSafe(|| {
        CertAuthority::load(cert, key, now_unix)
    })) {
        Ok(Ok(authority)) => {
            *handle_out = Box::into_raw(Box::new(authority));
            write_payload(Vec::new(), out, out_len);
            STATUS_OK
        }
        Ok(Err(message)) => {
            write_error(&message, out, out_len);
            STATUS_OPERATION
        }
        Err(_) => {
            write_error("certificate load panicked", out, out_len);
            STATUS_OPERATION
        }
    }
}

/// The CA certificate PEM.
///
/// # Safety
///
/// The handle must be valid for the call and the out pointers writable.
#[no_mangle]
pub unsafe extern "C" fn diting_cert_ca_pem(
    handle: *const CertAuthority,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let Some(authority) = handle.as_ref() else {
        return STATUS_BAD_ARGUMENT;
    };
    let payload = {
        let mut writer = PayloadWriter::new();
        writer.text(authority.ca_pem());
        writer.finish()
    };
    write_payload(payload, out, out_len);
    STATUS_OK
}

/// Mints one leaf certificate for `host`.
///
/// # Safety
///
/// The host must be readable for `host_len` bytes, the handle valid for the call and the out
/// pointers writable.
#[no_mangle]
pub unsafe extern "C" fn diting_cert_issue(
    handle: *const CertAuthority,
    host: *const u8,
    host_len: usize,
    now_unix: i64,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out.is_null() || out_len.is_null() {
        return STATUS_BAD_ARGUMENT;
    }
    let (Some(authority), Some(host)) = (handle.as_ref(), text(host, host_len)) else {
        return if handle.is_null() {
            STATUS_BAD_ARGUMENT
        } else {
            STATUS_BAD_PAYLOAD
        };
    };
    let result = catch_unwind(AssertUnwindSafe(|| authority.issue(host, now_unix)));
    match result {
        Ok(Ok(IssuedLeaf {
            chain_pem,
            key_pem,
            not_after_unix,
        })) => {
            let payload = {
                let mut writer = PayloadWriter::new();
                writer.text(&chain_pem);
                writer.text(&key_pem);
                writer.i64(not_after_unix);
                writer.finish()
            };
            write_payload(payload, out, out_len);
            STATUS_OK
        }
        Ok(Err(message)) => {
            write_error(&message, out, out_len);
            STATUS_OPERATION
        }
        Err(_) => {
            write_error("certificate issuance panicked", out, out_len);
            STATUS_OPERATION
        }
    }
}

/// `isExtendedValidation` over a comma separated policy list; `1` when the certificate is EV.
///
/// # Safety
///
/// The text must be readable for `csv_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_cert_is_ev(csv: *const u8, csv_len: usize) -> u32 {
    let Some(csv) = text(csv, csv_len) else {
        return 0;
    };
    match catch_unwind(AssertUnwindSafe(|| is_extended_validation_csv(csv))) {
        Ok(true) => 1,
        _ => 0,
    }
}

/// Drops a handle created by [`diting_cert_generate`] or [`diting_cert_load`].
///
/// # Safety
///
/// The handle must come from this library and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_cert_free(handle: *mut CertAuthority) {
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
pub unsafe extern "C" fn diting_cert_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Borrows a UTF-8 text argument. Go hands these into a call and never keeps the pointer.
unsafe fn text<'a>(pointer: *const u8, length: usize) -> Option<&'a str> {
    if length == 0 {
        return Some("");
    }
    if pointer.is_null() {
        return None;
    }
    std::str::from_utf8(slice::from_raw_parts(pointer, length)).ok()
}

struct PayloadWriter {
    buffer: Vec<u8>,
}

impl PayloadWriter {
    fn new() -> Self {
        PayloadWriter { buffer: Vec::new() }
    }

    fn text(&mut self, value: &str) {
        self.buffer
            .extend_from_slice(&(value.len() as u32).to_le_bytes());
        self.buffer.extend_from_slice(value.as_bytes());
    }

    fn i64(&mut self, value: i64) {
        self.buffer.extend_from_slice(&value.to_le_bytes());
    }

    fn finish(self) -> Vec<u8> {
        self.buffer
    }
}

fn write_error(message: &str, out: *mut *mut u8, out_len: *mut usize) {
    let payload = {
        let mut writer = PayloadWriter::new();
        writer.text(message);
        writer.finish()
    };
    write_payload(payload, out, out_len);
}

/// Hands `payload` to the caller as a boxed slice it frees with [`diting_cert_free_bytes`].
fn write_payload(payload: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = payload.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    unsafe {
        *out = pointer;
        *out_len = length;
    }
}

#[cfg(test)]
mod tests;
