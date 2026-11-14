//! C ABI for the webhook kernel: `magic "DWH1" | abi` then a JSON answer.
//!
//! Requests and answers are JSON so the `dart:ffi` caller stays a thin codec. Two ops:
//! `webhook.sign` and `webhook.retry` (see [`crate::sign`] / [`crate::retry_after`]).

use serde_json::{json, Value};

pub const ABI_VERSION: u32 = 1;
const MAGIC: u32 = u32::from_le_bytes(*b"DWH1");

fn handle_operation(request: &Value) -> Option<Value> {
    match request.get("op")?.as_str()? {
        "webhook.sign" => {
            let secret = request.get("secret").and_then(Value::as_str).unwrap_or("");
            let body = request.get("body").and_then(Value::as_str).unwrap_or("");
            let timestamp = request
                .get("timestamp")
                .and_then(Value::as_i64)
                .unwrap_or(0);
            let signature = crate::sign(secret, body, timestamp);
            Some(json!({ "signature": signature }))
        }
        "webhook.retry" => {
            let attempt = request.get("attempt").and_then(Value::as_i64).unwrap_or(1);
            let status = request.get("status").and_then(Value::as_i64);
            let base_ms = request.get("baseMs").and_then(Value::as_i64).unwrap_or(1000);
            let max_ms = request.get("maxMs").and_then(Value::as_i64).unwrap_or(30000);
            let max_attempts = request
                .get("maxAttempts")
                .and_then(Value::as_i64)
                .unwrap_or(3);
            let decision = crate::retry_after(attempt, status, base_ms, max_ms, max_attempts);
            Some(json!({ "retry": decision.retry, "delayMs": decision.delay_ms }))
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
pub unsafe extern "C" fn diting_webhook_core_call(
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

#[no_mangle]
pub extern "C" fn diting_webhook_core_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn diting_webhook_core_alloc(size: usize) -> *mut u8 {
    let mut buffer = vec![0u8; size];
    let pointer = buffer.as_mut_ptr();
    std::mem::forget(buffer);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_webhook_core_alloc`] (or a returned buffer) exactly once.
#[no_mangle]
pub unsafe extern "C" fn diting_webhook_core_free(pointer: *mut u8, size: usize) {
    if !pointer.is_null() && size > 0 {
        drop(Vec::from_raw_parts(pointer, size, size));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(value: Value) -> Value {
        handle_operation(&value).expect("operation returns an answer")
    }

    #[test]
    fn sign_op_returns_prefixed_hex() {
        let answer = call(json!({
            "op": "webhook.sign",
            "secret": "key",
            "body": "{\"a\":1}",
            "timestamp": 1700000000i64
        }));
        let signature = answer.get("signature").and_then(Value::as_str).unwrap();
        assert!(signature.starts_with("sha256="));
        assert_eq!(signature.len(), "sha256=".len() + 64);
    }

    #[test]
    fn retry_op_reports_delay() {
        let answer = call(json!({
            "op": "webhook.retry",
            "attempt": 2,
            "status": 503,
            "baseMs": 1000,
            "maxMs": 30000,
            "maxAttempts": 3
        }));
        assert_eq!(answer.get("retry").and_then(Value::as_bool), Some(true));
        assert_eq!(answer.get("delayMs").and_then(Value::as_i64), Some(2000));
    }

    #[test]
    fn unknown_op_is_rejected() {
        assert!(handle_operation(&json!({ "op": "nope" })).is_none());
    }
}
