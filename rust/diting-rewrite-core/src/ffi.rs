//! The C ABI the Go service drives (see `desktop/service/internal/core/rewrite_native.go`).
//!
//! | symbol | meaning |
//! | --- | --- |
//! | `diting_rewrite_abi_version` | ABI number the loader validates |
//! | `diting_rewrite_build_record` | build one record from a [`Request`], returns the reply payload |
//! | `diting_rewrite_record_types` | the supported type names, sorted |
//! | `diting_rewrite_engine_build` | compile an engine snapshot, returns a handle plus warnings |
//! | `diting_rewrite_engine_lookup` | answer one query from a handle |
//! | `diting_rewrite_engine_ptr_lookup` | PTR targets for one address |
//! | `diting_rewrite_engine_reverse_lookup` | first PTR target for one address |
//! | `diting_rewrite_engine_free` | drop an engine handle |
//! | `diting_rewrite_free_bytes` | drop a payload this library returned |
//!
//! Status words: `0` success, `1` rejected (payload carries the reason as UTF-8), `2` bad arguments
//! (null pointer, wrong length). The single-record entry point caches nothing between calls; the
//! engine entry points cache the compiled rules in a handle Go owns and swaps on configuration
//! change.

use std::slice;

use crate::engine::Engine;
use crate::payload::{
    decode_engine_config, decode_request, encode_engine_build, encode_engine_domains,
    encode_engine_lookup, encode_engine_reverse, encode_reply, encode_type_names,
};
use crate::record;

/// Must match `rewriteNativeABIVersion` in `desktop/service/internal/core/rewrite_native.go`.
pub const ABI_VERSION: u32 = 2;

const STATUS_OK: u32 = 0;
const STATUS_REJECTED: u32 = 1;
const STATUS_BAD_ARGS: u32 = 2;

/// ABI version of the library.
#[no_mangle]
pub extern "C" fn diting_rewrite_abi_version() -> u32 {
    ABI_VERSION
}

/// Builds the record a [`Request`] describes.
///
/// On `STATUS_OK` the payload is a [`crate::payload::encode_reply`] reply — which may say "no record
/// for this query type". On `STATUS_REJECTED` it is the error message.
///
/// # Safety
///
/// `input` must be readable for `input_len` bytes; `payload_out`/`payload_len` must be valid for
/// writes.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_build_record(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if input.is_null() && input_len > 0 {
        return STATUS_BAD_ARGS;
    }

    let data = if input_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input, input_len)
    };

    match build_reply(data) {
        Ok(payload) => {
            write_payload(payload, payload_out, payload_len);
            STATUS_OK
        }
        Err(message) => {
            write_payload(message.into_bytes(), payload_out, payload_len);
            STATUS_REJECTED
        }
    }
}

/// The supported record type names, sorted, in the [`crate::payload::encode_type_names`] layout.
///
/// # Safety
///
/// `payload_out`/`payload_len` must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_record_types(
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    write_payload(
        encode_type_names(record::type_names()),
        payload_out,
        payload_len,
    );
    STATUS_OK
}

/// Frees a payload returned by this library.
///
/// # Safety
///
/// `pointer`/`length` must be a pair this library produced and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

/// Compiles an engine snapshot.
///
/// On `STATUS_OK` `handle_out` receives an owned handle and the payload is the warning list. On
/// `STATUS_REJECTED` the payload is the error message and no handle is produced.
///
/// # Safety
///
/// `input` must be readable for `input_len` bytes; `handle_out` must be writable and
/// `payload_out`/`payload_len` must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_build(
    input: *const u8,
    input_len: usize,
    handle_out: *mut *mut Engine,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle_out.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if input.is_null() && input_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let data = if input_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input, input_len)
    };
    match decode_engine_config(data) {
        Ok(config) => {
            let (engine, warnings) = Engine::build(&config);
            *handle_out = Box::into_raw(Box::new(engine));
            write_payload(encode_engine_build(&warnings), payload_out, payload_len);
            STATUS_OK
        }
        Err(error) => {
            write_payload(error.0.into_bytes(), payload_out, payload_len);
            STATUS_REJECTED
        }
    }
}

/// Drops an engine handle.
///
/// # Safety
///
/// `handle` must come from [`diting_rewrite_engine_build`] and not be freed yet.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_free(handle: *mut Engine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Answers one query from an engine handle.
///
/// # Safety
///
/// `handle` must be a live handle; `name` must be readable for `name_len` bytes; `payload_out`/
/// `payload_len` must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_lookup(
    handle: *mut Engine,
    name: *const u8,
    name_len: usize,
    qtype: u16,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if name.is_null() && name_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let bytes = if name_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(name, name_len)
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        write_payload(
            "query name is not valid UTF-8".as_bytes().to_vec(),
            payload_out,
            payload_len,
        );
        return STATUS_REJECTED;
    };
    let result = (*handle).lookup(text, qtype);
    write_payload(encode_engine_lookup(&result), payload_out, payload_len);
    STATUS_OK
}

/// Returns the PTR targets of one address (4 or 16 raw bytes).
///
/// # Safety
///
/// `handle` must be a live handle; `ip` must be readable for `ip_len` bytes; `payload_out`/
/// `payload_len` must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_ptr_lookup(
    handle: *mut Engine,
    ip: *const u8,
    ip_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if ip.is_null() && ip_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let bytes = if ip_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(ip, ip_len)
    };
    write_payload(
        encode_engine_domains(&(*handle).lookup_ptr(bytes)),
        payload_out,
        payload_len,
    );
    STATUS_OK
}

/// Returns the first PTR target of one address (4 or 16 raw bytes).
///
/// # Safety
///
/// `handle` must be a live handle; `ip` must be readable for `ip_len` bytes; `payload_out`/
/// `payload_len` must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_reverse_lookup(
    handle: *mut Engine,
    ip: *const u8,
    ip_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if ip.is_null() && ip_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let bytes = if ip_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(ip, ip_len)
    };
    let domain = (*handle).lookup_reverse(bytes);
    let reply = if domain.is_empty() {
        encode_engine_reverse(None)
    } else {
        encode_engine_reverse(Some(&domain))
    };
    write_payload(reply, payload_out, payload_len);
    STATUS_OK
}

/// Decodes the request, builds the record and encodes the reply.
fn build_reply(data: &[u8]) -> Result<Vec<u8>, String> {
    let request = decode_request(data).map_err(|error| error.0)?;
    let record = record::build(
        &request.owner,
        request.qtype,
        &request.type_name,
        &request.value,
        request.ttl,
    )?;
    Ok(encode_reply(record.as_ref()))
}

/// Hands a `Vec<u8>` to the caller; the length travels with the pointer so the caller can rebuild
/// the same allocation in [`diting_rewrite_free_bytes`].
unsafe fn write_payload(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = bytes.into_boxed_slice();
    *out_len = boxed.len();
    *out = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

#[cfg(test)]
mod tests;
