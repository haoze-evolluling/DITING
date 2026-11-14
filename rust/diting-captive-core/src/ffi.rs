//! C ABI for a `dart:ffi` caller. `op` selects the request shape; the payload header stays fixed —
//! `magic "DCP1" | abi`.

use serde_json::{json, Value};

use crate::evaluate::{self, Probe};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DCP1");

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
        status_code: source
            .get("statusCode")
            .and_then(Value::as_u64)
            .map(|n| n as u16),
        redirect_url: opt_string(source.get("redirectUrl")),
        body_matches_expected: source
            .get("bodyMatchesExpected")
            .and_then(Value::as_bool),
    }
}

fn handle_operation(request: &Value) -> Option<Value> {
    match request.get("op")?.as_str()? {
        "captive.evaluate" => {
            let verdict = evaluate::evaluate(&decode_probe(request));
            Some(json!({
                "state": verdict.state.as_str(),
                "portalUrl": verdict.portal_url,
                "suspendBlocking": verdict.suspend_blocking,
            }))
        }
        "captive.parseOption" => {
            let option = request.get("option").and_then(Value::as_str).unwrap_or("");
            Some(json!({ "url": evaluate::parse_portal_url(option) }))
        }
        "captive.gate" => {
            let verdict = evaluate::evaluate(&decode_probe(request));
            let validated = request
                .get("networkValidated")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let capable = request
                .get("captiveCapability")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let decision = evaluate::gate(validated, capable, &verdict);
            Some(json!({
                "suspendBlocking": decision.suspend_blocking,
                "portalUrl": decision.portal_url,
                "reason": decision.reason,
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
pub unsafe extern "C" fn diting_captive_core_call(
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
pub extern "C" fn diting_captive_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes; release with [`diting_captive_core_free`].
#[no_mangle]
pub extern "C" fn diting_captive_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_captive_core_alloc`] or a `*_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_captive_core_free(pointer: *mut u8, size: usize) {
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
    fn evaluates_redirect_portal() {
        let request = json!({
            "op": "captive.evaluate",
            "probe": { "statusCode": 302, "redirectUrl": "http://portal/login" }
        });
        let answer = handle_operation(&request).unwrap();
        assert_eq!(answer["state"], json!("portal"));
        assert_eq!(answer["suspendBlocking"], json!(true));
    }

    #[test]
    fn parses_option() {
        let answer = handle_operation(&json!({
            "op": "captive.parseOption",
            "option": "https://wifi.example/login"
        }))
        .unwrap();
        assert_eq!(answer["url"], json!("https://wifi.example/login"));
    }

    #[test]
    fn ffi_round_trip() {
        let request = json!({
            "op": "captive.evaluate",
            "probe": { "statusCode": 204, "bodyMatchesExpected": true }
        })
        .to_string();
        let mut out_len = 0usize;
        let pointer =
            unsafe { diting_captive_core_call(request.as_ptr(), request.len(), &mut out_len) };
        assert!(!pointer.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(pointer, out_len) };
        assert_eq!(&bytes[0..4], b"DCP1");
        let value: Value = serde_json::from_slice(&bytes[8..]).unwrap();
        assert_eq!(value["state"], json!("open"));
        unsafe { diting_captive_core_free(pointer, out_len) };
    }
}
