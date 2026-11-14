//! C ABI for the `dart:ffi` caller.
//!
//! One entry (`call`) with an `op` field decides the request shape; payloads are JSON and the
//! header stays fixed — `magic "DSC1" | abi` — so the Dart loader refuses a mismatched library.

use serde_json::{json, Value};

use crate::fetch;
use crate::health;
use crate::model;
use crate::payload;
use crate::schedule;
use crate::url::{self, UrlParts};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DSC1");

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

fn payload(answer: Value) -> Vec<u8> {
    let mut bytes = header();
    bytes.extend_from_slice(answer.to_string().as_bytes());
    bytes
}

fn error(value: url::UrlError) -> Value {
    json!({ "error": value.as_str() })
}

fn mirror_error(value: url::MirrorError) -> Value {
    json!({ "error": value.as_str() })
}

fn handle_operation(request: &Value) -> Option<Value> {
    let op = request.get("op")?.as_str()?;
    let answer = match op {
        "url.validate" => {
            let address = payload::text_or_empty(request, "url");
            match url::validate(&address, &UrlParts::from(request)) {
                Ok(()) => json!({ "error": null }),
                Err(kind) => error(kind),
            }
        }
        "url.name" => {
            let address = payload::text_or_empty(request, "url");
            json!({
                "name": url::extract_name(
                    &address,
                    &payload::text_or_empty(request, "path"),
                    &payload::text_or_empty(request, "host"),
                ),
            })
        }
        "url.lines" => json!({
            "count": url::count_effective_lines(&payload::text_or_empty(request, "content")),
        }),
        "url.build" => {
            let parts = UrlParts::from(request);
            if !parts.parsed {
                json!({ "error": "rawUrl" })
            } else {
                let template = payload::text_or_empty(request, "template");
                let address = payload::text_or_empty(request, "url");
                match url::build_mirror(&template, &address, &parts) {
                    Ok(built) => json!({ "url": built }),
                    Err(kind) => mirror_error(kind),
                }
            }
        }
        "url.normalize" => {
            match url::normalize_template(request.get("template").and_then(Value::as_str)) {
                Ok(template) => json!({ "template": template }),
                Err(kind) => mirror_error(kind),
            }
        }
        "model.records" => json!({ "items": model::rows(request, "records") }),
        "model.groups" => json!({ "items": model::rows(request, "groups") }),
        "model.items" => json!({ "items": model::rows(request, "items") }),
        "prepare.add" => model::prepare_add(request),
        "prepare.edit" => model::prepare_edit(request),
        "prepare.mirror" => model::prepare_mirror(request),
        "fetch.targets" => fetch::targets(request),
        "fetch.verdict" => fetch::verdict(request),
        "fetch.headers" => fetch::headers(request),
        "health.classify" => health::classify_request(request),
        "health.summary" => health::summary_request(request),
        "schedule.evaluate" => schedule::evaluate(request)?,
        _ => return None,
    };
    Some(answer)
}

/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_subscription_core_call(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let request: Option<Value> = serde_json::from_slice(input_at(text, len)).ok();
    let answer = request.as_ref().and_then(handle_operation).map(payload);
    respond(answer, out_len)
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_subscription_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill; release it with
/// [`diting_subscription_core_free`].
#[no_mangle]
pub extern "C" fn diting_subscription_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_subscription_core_alloc`] or a `_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_subscription_core_free(pointer: *mut u8, size: usize) {
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

    fn call(request: Value) -> Value {
        handle_operation(&request).expect("op rejected")
    }

    #[test]
    fn unknown_op_rejected() {
        assert!(handle_operation(&json!({ "op": "nope" })).is_none());
    }

    #[test]
    fn validate_and_build() {
        let request = json!({
            "op": "url.validate",
            "url": "https://example.com/a",
            "urlParts": {
                "parsed": true, "hasScheme": true, "scheme": "https",
                "host": "example.com", "path": "/a", "query": ""
            },
        });
        assert_eq!(call(request)["error"], Value::Null);
        let built = call(json!({
            "op": "url.build",
            "template": "https://m/{host}{path}",
            "url": "https://example.com/a",
            "urlParts": {
                "parsed": true, "hasScheme": true, "scheme": "https",
                "host": "example.com", "path": "/a", "query": ""
            },
        }));
        assert_eq!(built["url"], json!("https://m/example.com/a"));
    }
}
