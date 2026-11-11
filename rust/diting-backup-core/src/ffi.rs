//! C ABI for the `dart:ffi` caller.
//!
//! Two entries, one call per user action. The payload is JSON — the file itself is JSON, so a
//! binary layout would only re-encode it on both sides of the boundary. The header stays fixed:
//! `magic "DBK1" | abi`, then the JSON text, so the Dart loader refuses a library whose version
//! does not match what it was compiled against.

use crate::export;
use crate::import;

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DBK1");

fn header() -> Vec<u8> {
    let mut bytes = Vec::with_capacity(8);
    bytes.extend_from_slice(&MAGIC.to_le_bytes());
    bytes.extend_from_slice(&ABI_VERSION.to_le_bytes());
    bytes
}

/// Hands `bytes` to the caller as a pointer/length pair; shrinking keeps the length enough to
/// rebuild the allocation in [`diting_backup_core_free`].
fn into_buffer(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (pointer, length)
}

/// # Safety
/// `out_len` must be writable; `bytes` is either `None` (unnamed failure, reported as null) or a
/// finished buffer whose ownership moves to the caller.
unsafe fn respond(bytes: Option<Vec<u8>>, out_len: *mut usize) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    match bytes {
        Some(bytes) => {
            let (pointer, length) = into_buffer(bytes);
            *out_len = length;
            pointer
        }
        None => {
            *out_len = 0;
            std::ptr::null_mut()
        }
    }
}

/// # Safety
/// `text` must point to `len` readable bytes.
unsafe fn input_at<'a>(text: *const u8, len: usize) -> &'a [u8] {
    if text.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(text, len)
    }
}

fn payload(answer: serde_json::Value) -> Vec<u8> {
    let mut bytes = header();
    bytes.extend_from_slice(answer.to_string().as_bytes());
    bytes
}

/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload.
unsafe fn call(
    text: *const u8,
    len: usize,
    handler: fn(&serde_json::Value) -> serde_json::Value,
) -> Option<Vec<u8>> {
    let raw = input_at(text, len);
    let request: serde_json::Value = serde_json::from_slice(raw).ok()?;
    Some(payload(handler(&request)))
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_backup_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill. `dart:ffi` has no allocator of its own;
/// release it with [`diting_backup_core_free`].
#[no_mangle]
pub extern "C" fn diting_backup_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_backup_core_alloc`] or a `diting_backup_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_backup_core_free(pointer: *mut u8, size: usize) {
    if pointer.is_null() || size == 0 {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, size,
    )));
}

/// Builds the backup file. In: `{nowMs, groups, fields}`. Out: `{content, included, counts,
/// skipped}`.
///
/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_backup_core_export(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    respond(call(text, len, export::run), out_len)
}

/// Validates and merges a backup file. In: `{content, nowMs, hasDatabase, current}`. Out: the import
/// plan (see [`crate::import`]).
///
/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_backup_core_import(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    respond(call(text, len, import::run), out_len)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_carries_magic_and_version() {
        let bytes = header();
        assert_eq!(&bytes[0..4], b"DBK1");
        assert_eq!(
            u32::from_le_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]),
            ABI_VERSION
        );
    }

    #[test]
    fn a_rejected_payload_is_null() {
        let mut length = 7usize;
        let text = b"not json";
        let pointer = unsafe { diting_backup_core_export(text.as_ptr(), text.len(), &mut length) };
        assert!(pointer.is_null());
        assert_eq!(length, 0);
    }

    #[test]
    fn export_round_trips_through_the_boundary() {
        let request = serde_json::json!({
            "nowMs": 1,
            "groups": ["excluded"],
            "fields": {"excluded": {"packages": ["com.a"]}},
        })
        .to_string();
        let mut length = 0usize;
        let pointer =
            unsafe { diting_backup_core_export(request.as_ptr(), request.len(), &mut length) };
        assert!(!pointer.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(pointer, length) }.to_vec();
        unsafe { diting_backup_core_free(pointer, length) };
        assert_eq!(&bytes[0..4], b"DBK1");
        let answer: serde_json::Value = serde_json::from_slice(&bytes[8..]).expect("json");
        assert_eq!(answer["included"], serde_json::json!(["excluded"]));
        assert_eq!(answer["counts"]["excluded"], serde_json::json!(1));
    }
}
