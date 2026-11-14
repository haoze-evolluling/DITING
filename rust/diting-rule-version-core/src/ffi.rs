//! C ABI for a `dart:ffi` caller. `op` selects the request shape; the payload header stays fixed —
//! `magic "DRV1" | abi`.

use serde_json::{json, Value};

use crate::version::{self, VersionEntry};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DRV1");

fn text_list(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn decode_versions(value: Option<&Value>) -> Vec<VersionEntry> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    Some(VersionEntry {
                        hash: item.get("hash")?.as_str()?.to_string(),
                        rule_count: item.get("ruleCount").and_then(Value::as_i64).unwrap_or(0),
                        created_at: item.get("createdAt").and_then(Value::as_i64).unwrap_or(0),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn encode_versions(entries: &[VersionEntry]) -> Value {
    Value::Array(
        entries
            .iter()
            .map(|entry| {
                json!({
                    "hash": entry.hash,
                    "ruleCount": entry.rule_count,
                    "createdAt": entry.created_at,
                })
            })
            .collect(),
    )
}

fn handle_operation(request: &Value) -> Option<Value> {
    match request.get("op")?.as_str()? {
        "ruleversion.diff" => {
            let old = text_list(request.get("old"));
            let new = text_list(request.get("new"));
            let diff = version::diff(&old, &new);
            Some(json!({
                "added": diff.added,
                "removed": diff.removed,
                "addedCount": diff.added_count,
                "removedCount": diff.removed_count,
                "unchangedCount": diff.unchanged_count,
                "delta": diff.delta,
            }))
        }
        "ruleversion.record" => {
            let existing = decode_versions(request.get("versions"));
            let hash = request.get("hash")?.as_str()?;
            let rule_count = request
                .get("ruleCount")
                .and_then(Value::as_i64)
                .unwrap_or(0);
            let created_at = request
                .get("createdAt")
                .and_then(Value::as_i64)
                .unwrap_or(0);
            let max = request
                .get("max")
                .and_then(Value::as_u64)
                .map(|n| n as usize);
            let next = version::record(&existing, hash, rule_count, created_at, max);
            Some(json!({ "versions": encode_versions(&next) }))
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
pub unsafe extern "C" fn diting_rule_version_core_call(
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
pub extern "C" fn diting_rule_version_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes; release with [`diting_rule_version_core_free`].
#[no_mangle]
pub extern "C" fn diting_rule_version_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_rule_version_core_alloc`] or a `*_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_version_core_free(pointer: *mut u8, size: usize) {
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
    fn diffs_two_rule_sets() {
        let request = json!({
            "op": "ruleversion.diff",
            "old": ["ads.com", "track.net"],
            "new": ["track.net", "new.example"],
        });
        let answer = handle_operation(&request).unwrap();
        assert_eq!(answer["added"], json!(["new.example"]));
        assert_eq!(answer["removed"], json!(["ads.com"]));
        assert_eq!(answer["addedCount"], json!(1));
    }

    #[test]
    fn records_versions_newest_first() {
        let request = json!({
            "op": "ruleversion.record",
            "versions": [{ "hash": "h1", "ruleCount": 5, "createdAt": 100 }],
            "hash": "h2",
            "ruleCount": 6,
            "createdAt": 200,
            "max": 5,
        });
        let answer = handle_operation(&request).unwrap();
        let versions = answer["versions"].as_array().unwrap();
        assert_eq!(versions.len(), 2);
        assert_eq!(versions[0]["hash"], json!("h2"));
    }

    #[test]
    fn ffi_round_trip() {
        let request = json!({
            "op": "ruleversion.diff",
            "old": ["a"],
            "new": ["a", "b"],
        })
        .to_string();
        let mut out_len = 0usize;
        let pointer =
            unsafe { diting_rule_version_core_call(request.as_ptr(), request.len(), &mut out_len) };
        assert!(!pointer.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(pointer, out_len) };
        assert_eq!(&bytes[0..4], b"DRV1");
        let value: Value = serde_json::from_slice(&bytes[8..]).unwrap();
        assert_eq!(value["added"], json!(["b"]));
        unsafe { diting_rule_version_core_free(pointer, out_len) };
    }
}
