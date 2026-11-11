//! C ABI for the `dart:ffi` caller.
//!
//! Three entries share one `call`: `plan` (SQL + args), `rows` (typed rows) and `derive`
//! (aggregates), plus the small `classify` helpers the Dart models expose. The header is fixed —
//! `magic "DLQ1" | abi` — so a mismatched library is rejected by the loader.

use serde_json::{json, Value};

use crate::classify;
use crate::derive;
use crate::payload;
use crate::rows;
use crate::sql;

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DLQ1");

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

fn classify_op(request: &Value) -> Option<Value> {
    let op = request.get("op")?.as_str()?;
    let query_type = payload::integer_or(request, "queryType", 0);
    let query_name = payload::text_or_empty(request, "queryName");
    let message = payload::text(request, "message");
    let result = payload::text_or_empty(request, "result");
    let outcome = payload::text_or_empty(request, "outcome");
    let connection = classify::dns_is_connection(query_type, &query_name, message.as_deref());
    let blocked = classify::dns_is_blocked(&result, message.as_deref());
    let rewritten = classify::dns_is_rewritten(&result, message.as_deref());
    Some(match op {
        "classify.dnsConnection" => json!({ "value": connection }),
        "classify.dnsLogStatus" => json!({
            "status": classify::dns_log_status(
                &result,
                payload::flag_or(request, "isConnection", false),
                payload::flag_or(request, "cached", false),
            ),
        }),
        "classify.dnsRow" => json!({
            "isConnection": connection,
            "isBlocked": blocked,
            "isRewritten": rewritten,
            "status": classify::dns_request_status(&result, connection, blocked, rewritten),
            "messageFields": classify::dns_message(message.as_deref()),
        }),
        "classify.httpRequestStatus" => json!({
            "status": classify::http_request_status(&outcome),
        }),
        "classify.httpLogStatus" => json!({
            "status": classify::http_log_status(&outcome),
        }),
        "classify.httpPassed" => json!({
            "value": classify::http_outcome_is_passed(&outcome),
        }),
        "classify.dnsMessage" => classify::dns_message(message.as_deref()),
        "classify.dnsElapsed" => json!({
            "value": classify::elapsed_ms(message.as_deref()),
        }),
        _ => return None,
    })
}

fn handle_operation(request: &Value) -> Option<Value> {
    let op = request.get("op")?.as_str()?;
    match op {
        "plan" => sql::plan(request),
        "rows" => rows::rows(request),
        "derive" => derive::derive(request),
        other if other.starts_with("classify.") => classify_op(request),
        _ => None,
    }
}

/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_log_query_core_call(
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
pub extern "C" fn diting_log_query_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill; release it with
/// [`diting_log_query_core_free`].
#[no_mangle]
pub extern "C" fn diting_log_query_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_log_query_core_alloc`] or a `_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_log_query_core_free(pointer: *mut u8, size: usize) {
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
    fn unknown_ops_are_rejected() {
        assert!(handle_operation(&json!({ "op": "nope" })).is_none());
        assert!(handle_operation(&json!({ "op": "plan", "name": "nope" })).is_none());
    }

    #[test]
    fn classify_ops() {
        let answer = handle_operation(&json!({
            "op": "classify.dnsRow",
            "queryType": 1,
            "queryName": "x",
            "result": "PASSED",
            "message": "elapsed=5ms",
        }))
        .unwrap();
        assert_eq!(answer["status"], json!("passed"));
        assert_eq!(answer["messageFields"]["elapsedMs"], json!(5));
    }
}
