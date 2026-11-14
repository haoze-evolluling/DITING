//! C ABI for the `dart:ffi` caller. One `call` entry keyed by `op`, JSON payloads with the fixed
//! `magic "DLA1" | abi` header.

use serde_json::{json, Value};

use crate::policy::{self, RouteOutcome};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DLA1");

fn string(request: &Value, key: &str) -> String {
    request
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn handle_operation(request: &Value) -> Option<Value> {
    match request.get("op")?.as_str()? {
        "localapi.validateBind" => {
            let bind = string(request, "bind");
            Some(match policy::validate_bind(&bind) {
                Ok(()) => json!({ "ok": true }),
                Err(error) => json!({ "ok": false, "error": error }),
            })
        }
        "localapi.authorize" => {
            let provided = request.get("token").and_then(Value::as_str);
            let decision = policy::authorize(
                &string(request, "bind"),
                &string(request, "clientIp"),
                &string(request, "expectedToken"),
                provided,
            );
            Some(json!({ "decision": decision.as_str() }))
        }
        "localapi.route" => {
            let outcome = policy::route(&string(request, "method"), &string(request, "path"));
            Some(match outcome {
                RouteOutcome::Found(route) => json!({ "outcome": "found", "route": route.id() }),
                RouteOutcome::MethodNotAllowed => json!({ "outcome": "method_not_allowed" }),
                RouteOutcome::NotFound => json!({ "outcome": "not_found" }),
            })
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
/// `out_len` must be writable; `bytes` is `None` or a finished buffer whose ownership moves out.
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
pub unsafe extern "C" fn diting_localapi_core_call(
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
pub extern "C" fn diting_localapi_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes; release with [`diting_localapi_core_free`].
#[no_mangle]
pub extern "C" fn diting_localapi_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_localapi_core_alloc`] or a `*_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_localapi_core_free(pointer: *mut u8, size: usize) {
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
    fn authorizes_a_loopback_token() {
        let answer = handle_operation(&json!({
            "op": "localapi.authorize",
            "bind": "127.0.0.1",
            "clientIp": "127.0.0.1",
            "expectedToken": "t",
            "token": "t",
        }))
        .unwrap();
        assert_eq!(answer["decision"], json!("allow"));
    }

    #[test]
    fn ffi_round_trip() {
        let request = json!({
            "op": "localapi.route",
            "method": "GET",
            "path": "/status",
        })
        .to_string();
        let mut out_len = 0usize;
        let pointer =
            unsafe { diting_localapi_core_call(request.as_ptr(), request.len(), &mut out_len) };
        assert!(!pointer.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(pointer, out_len) };
        assert_eq!(&bytes[0..4], b"DLA1");
        let value: Value = serde_json::from_slice(&bytes[8..]).unwrap();
        assert_eq!(value["route"], json!("status"));
        unsafe { diting_localapi_core_free(pointer, out_len) };
    }
}
