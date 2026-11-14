//! C ABI for a `dart:ffi` caller. One entry (`call`) with an `op` field decides the request shape;
//! payloads are JSON with the fixed `magic "DLK1" | abi` header.

use serde_json::{json, Value};

use crate::evaluate::{self, Probe};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DLK1");

fn opt_string(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

fn decode_probe(request: &Value) -> Probe {
    let source = request.get("probe").unwrap_or(request);
    Probe {
        observed_exit_id: opt_string(source.get("observedExitId")),
        expected_exit_id: opt_string(source.get("expectedExitId")),
        plaintext_dns_seen: source
            .get("plaintextDnsSeen")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        used_configured_upstream: source
            .get("usedConfiguredUpstream")
            .and_then(Value::as_bool),
    }
}

fn handle_operation(request: &Value) -> Option<Value> {
    match request.get("op")?.as_str()? {
        "leak.evaluate" => {
            let verdict = evaluate::evaluate(&decode_probe(request));
            Some(json!({
                "status": verdict.status.as_str(),
                "reason": verdict.reason,
            }))
        }
        _ => None,
    }
}

fn header() -> Vec<u8> {
    let mut bytes = Vec::with_capacity(8);
    bytes.extend_from_slice(&MAGIC.to_le_bytes());
    bytes.extend_from_slice(&ABI_VERSION.to_le_bytes());
    bytes
}

fn payload(answer: Value) -> Vec<u8> {
    let mut bytes = header();
    bytes.extend_from_slice(answer.to_string().as_bytes());
    bytes
}

fn into_buffer(mut bytes: Vec<u8>) -> (*mut u8, usize) {
    let length = bytes.len();
    let pointer = bytes.as_mut_ptr();
    std::mem::forget(bytes);
    (pointer, length)
}

/// # Safety
/// `out_len` must be writable; `bytes` is `None` (rejected payload, reported as null) or a finished
/// buffer whose ownership moves to the caller.
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
pub unsafe extern "C" fn diting_leak_core_call(
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
pub extern "C" fn diting_leak_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes; release with [`diting_leak_core_free`].
#[no_mangle]
pub extern "C" fn diting_leak_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_leak_core_alloc`] or a `*_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_leak_core_free(pointer: *mut u8, size: usize) {
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
    fn rejects_unknown_op() {
        assert!(handle_operation(&json!({ "op": "nope" })).is_none());
    }

    #[test]
    fn evaluates_a_proxied_probe() {
        let request = json!({
            "op": "leak.evaluate",
            "probe": {
                "observedExitId": "doh.example.",
                "expectedExitId": "doh.example",
                "plaintextDnsSeen": false,
                "usedConfiguredUpstream": true,
            }
        });
        let answer = handle_operation(&request).unwrap();
        assert_eq!(answer["status"], json!("pass"));
    }

    #[test]
    fn ffi_round_trip() {
        let request = json!({
            "op": "leak.evaluate",
            "probe": { "plaintextDnsSeen": true },
        })
        .to_string();
        let mut out_len = 0usize;
        let pointer =
            unsafe { diting_leak_core_call(request.as_ptr(), request.len(), &mut out_len) };
        assert!(!pointer.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(pointer, out_len) };
        assert_eq!(&bytes[0..4], b"DLK1");
        let value: Value = serde_json::from_slice(&bytes[8..]).unwrap();
        assert_eq!(value["status"], json!("leak"));
        unsafe { diting_leak_core_free(pointer, out_len) };
    }
}
