//! C ABI for a `dart:ffi` caller. One entry (`call`) with an `op` field decides the request shape;
//! payloads are JSON and the header stays fixed — `magic "DNP1" | abi` — so the Dart loader refuses a
//! mismatched library.

use serde_json::Value;

use crate::{payload, profile};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DNP1");

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

fn handle_operation(request: &Value) -> Option<Value> {
    match request.get("op")?.as_str()? {
        "netprofile.resolve" => {
            let context = payload::decode_context(request);
            let profiles = payload::decode_profiles(request);
            let fallback = payload::fallback_id(request);
            Some(profile::resolve(&context, &profiles, &fallback).to_json())
        }
        _ => None,
    }
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
pub unsafe extern "C" fn diting_netprofile_core_call(
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
pub extern "C" fn diting_netprofile_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes; release with [`diting_netprofile_core_free`].
#[no_mangle]
pub extern "C" fn diting_netprofile_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_netprofile_core_alloc`] or a `*_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_netprofile_core_free(pointer: *mut u8, size: usize) {
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
    fn resolves_wifi_profile() {
        let request = json!({
            "op": "netprofile.resolve",
            "networkCtx": { "type": "wifi", "metered": false, "ssid": "Home" },
            "profiles": [
                {
                    "id": "home",
                    "name": "家",
                    "priority": 100,
                    "networkMatch": { "types": ["wifi"], "ssid": "Home" },
                    "upstreamSet": "home-up",
                    "ruleGroupStates": ["ads"],
                    "featureToggles": { "blocking": true }
                }
            ]
        });
        let answer = handle_operation(&request).unwrap();
        assert_eq!(answer["matched"], json!(true));
        assert_eq!(answer["profileId"], json!("home"));
        assert_eq!(answer["upstreamSet"], json!("home-up"));
    }

    #[test]
    fn ffi_round_trip() {
        let request = json!({
            "op": "netprofile.resolve",
            "networkCtx": { "type": "cellular" },
            "profiles": [
                { "id": "mobile", "networkMatch": { "types": ["cellular"] }, "upstreamSet": "m" }
            ]
        })
        .to_string();
        let mut out_len = 0usize;
        let pointer = unsafe {
            diting_netprofile_core_call(request.as_ptr(), request.len(), &mut out_len)
        };
        assert!(!pointer.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(pointer, out_len) };
        assert_eq!(&bytes[0..4], b"DNP1");
        let value: Value = serde_json::from_slice(&bytes[8..]).unwrap();
        assert_eq!(value["profileId"], json!("mobile"));
        unsafe { diting_netprofile_core_free(pointer, out_len) };
    }
}
