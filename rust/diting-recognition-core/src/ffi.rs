//! C ABI for the `dart:ffi` caller: `plan`, `parse` and `avatarAccepted`, with the fixed
//! `magic "DRM1" | abi` header.

use serde_json::{json, Value};

use crate::members::parse_members;
use crate::plan::plan;

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DRM1");

fn header() -> Vec<u8> {
    let mut bytes = Vec::with_capacity(8);
    bytes.extend_from_slice(&MAGIC.to_le_bytes());
    bytes.extend_from_slice(&ABI_VERSION.to_le_bytes());
    bytes
}

fn into_buffer(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (pointer, length)
}

/// # Safety
/// `out_len` must be writable; `bytes` is either `None` (rejected payload, reported as null) or a
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

fn payload_of(answer: Value) -> Vec<u8> {
    let mut bytes = header();
    bytes.extend_from_slice(answer.to_string().as_bytes());
    bytes
}

fn handle_operation(request: &Value) -> Option<Value> {
    let plan = plan();
    match request.get("op")?.as_str()? {
        "plan" => Some(plan),
        "parse" => Some(parse_members(request.get("raw")?.as_str()?)),
        "avatarAccepted" => {
            let size = request.get("size")?.as_i64()?;
            let max = plan["maxAvatarBytes"].as_i64()?;
            Some(json!({ "value": size > 0 && size <= max }))
        }
        _ => None,
    }
}

/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_recognition_core_call(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let request: Option<Value> = serde_json::from_slice(input_at(text, len)).ok();
    let answer = request.as_ref().and_then(handle_operation).map(payload_of);
    respond(answer, out_len)
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_recognition_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill; release it with
/// [`diting_recognition_core_free`].
#[no_mangle]
pub extern "C" fn diting_recognition_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_recognition_core_alloc`] or a `_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_recognition_core_free(pointer: *mut u8, size: usize) {
    if pointer.is_null() || size == 0 {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, size,
    )));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operations_are_dispatched() {
        assert!(handle_operation(&json!({ "op": "plan" })).is_some());
        let parsed = handle_operation(&json!({
            "op": "parse",
            "raw": r#"{"version":1,"sponsors":[],"coBuilders":[]}"#,
        }))
        .unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(
            handle_operation(&json!({ "op": "avatarAccepted", "size": 1 })).unwrap()["value"],
            true
        );
        assert_eq!(
            handle_operation(&json!({ "op": "avatarAccepted", "size": 0 })).unwrap()["value"],
            false
        );
        assert_eq!(
            handle_operation(&json!({ "op": "avatarAccepted", "size": 1048577 })).unwrap()["value"],
            false
        );
        assert!(handle_operation(&json!({ "op": "nope" })).is_none());
    }
}
