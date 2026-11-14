//! C ABI for a `dart:ffi` caller.
//!
//! One entry (`call`) with an `op` field decides the request shape; payloads are JSON and the
//! header stays fixed — `magic "DSC2" | abi` — so the Dart loader refuses a mismatched library.
//! `diting-subscription-core` does not go through this: it depends on the crate directly.

use serde_json::Value;

use crate::schedule;

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DSC2");

fn header() -> Vec<u8> {
    let mut bytes = Vec::with_capacity(8);
    bytes.extend_from_slice(&MAGIC.to_le_bytes());
    bytes.extend_from_slice(&ABI_VERSION.to_le_bytes());
    bytes
}

fn into_buffer(mut bytes: Vec<u8>) -> (*mut u8, usize) {
    let length = bytes.len();
    let pointer = bytes.as_mut_ptr();
    std::mem::forget(bytes);
    (pointer, length)
}

fn payload(answer: Value) -> Vec<u8> {
    let mut bytes = header();
    bytes.extend_from_slice(answer.to_string().as_bytes());
    bytes
}

fn handle_operation(request: &Value) -> Option<Value> {
    match request.get("op")?.as_str()? {
        "schedule.evaluate" => schedule::evaluate(request),
        "schedule.rules" => {
            let now_ms = request.get("nowMs").and_then(Value::as_i64).unwrap_or(0);
            Some(schedule::evaluate_rules(now_ms, request))
        }
        _ => None,
    }
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
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_schedule_core_call(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let input = if text.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(text, len)
    };
    let request: Option<Value> = serde_json::from_slice(input).ok();
    let answer = request.as_ref().and_then(handle_operation).map(payload);
    respond(answer, out_len)
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_schedule_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill; release it with
/// [`diting_schedule_core_free`].
#[no_mangle]
pub extern "C" fn diting_schedule_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_schedule_core_alloc`] or a `_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_schedule_core_free(pointer: *mut u8, size: usize) {
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
    use serde_json::json;

    #[test]
    fn rejects_unknown_op() {
        assert!(handle_operation(&json!({ "op": "nope" })).is_none());
    }

    #[test]
    fn evaluates_interval_plan() {
        let request = json!({
            "op": "schedule.evaluate",
            "schedule": "interval",
            "intervalHours": 24,
            "nowMs": 100_i64 * 86_400_000,
            "nowDay": 100,
            "records": [{ "id": 7, "lastAttemptAt": 0 }],
        });
        let answer = handle_operation(&request).expect("evaluated");
        assert_eq!(answer["due"], json!([7]));
    }
}
