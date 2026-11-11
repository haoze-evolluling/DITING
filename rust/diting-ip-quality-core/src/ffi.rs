//! C ABI for the `dart:ffi` caller: `parseProbe`, `ipLike`, `sourceResult` and `summarize`, with
//! the fixed `magic "DIQ1" | abi` header.

use serde_json::{json, Value};

use crate::probe::{is_ip_like, parse_probe};
use crate::source::{source_result, Source};
use crate::summary::summarize;

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DIQ1");

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
    match request.get("op")?.as_str()? {
        "parseProbe" => Some(json!({ "ip": parse_probe(request.get("body")?.as_str()?) })),
        "ipLike" => Some(json!({
            "value": is_ip_like(request.get("value")?.as_str()?),
        })),
        "sourceResult" => {
            let source = Source::parse(request.get("source")?.as_str()?)?;
            let status = request.get("status")?.as_i64()?;
            let body = request.get("body")?.as_str()?;
            Some(source_result(source, status, body))
        }
        "summarize" => {
            let ip = request.get("ip")?.as_str()?;
            let sources = request.get("sources")?.as_array()?;
            Some(summarize(ip, sources))
        }
        _ => None,
    }
}

/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_ip_quality_core_call(
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
pub extern "C" fn diting_ip_quality_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill; release it with
/// [`diting_ip_quality_core_free`].
#[no_mangle]
pub extern "C" fn diting_ip_quality_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_ip_quality_core_alloc`] or a `_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_ip_quality_core_free(pointer: *mut u8, size: usize) {
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
        assert_eq!(
            handle_operation(&json!({ "op": "parseProbe", "body": "1.2.3.4" })).unwrap()["ip"],
            "1.2.3.4"
        );
        assert_eq!(
            handle_operation(&json!({ "op": "ipLike", "value": "::1" })).unwrap()["value"],
            true
        );
        let source = handle_operation(&json!({
            "op": "sourceResult",
            "source": "ipApi",
            "status": 200,
            "body": r#"{"status":"success","as":"AS15169 Google LLC","isp":"Google"}"#,
        }))
        .unwrap();
        assert_eq!(source["status"], "命中");
        let report = handle_operation(&json!({
            "op": "summarize",
            "ip": "1.2.3.4",
            "sources": [source],
        }))
        .unwrap();
        assert_eq!(report["ipType"], "机房");
        assert!(handle_operation(&json!({
            "op": "sourceResult",
            "source": "nope",
            "status": 200,
            "body": "",
        }))
        .is_none());
        assert!(handle_operation(&json!({ "op": "nope" })).is_none());
    }
}
