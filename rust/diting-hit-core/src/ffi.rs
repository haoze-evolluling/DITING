//! C ABI for the hit counter.
//!
//! One `call` entry chooses the operation; payloads are JSON with a fixed `magic "DHC1" | abi`
//! header so the loader refuses a mismatched library. A process-global tally backs every call.

use std::sync::OnceLock;

use serde_json::{json, Value};

use crate::counters::{HitCounters, HitEntry};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DHC1");

fn counters() -> &'static HitCounters {
    static COUNTERS: OnceLock<HitCounters> = OnceLock::new();
    COUNTERS.get_or_init(HitCounters::new)
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

fn entry_json(entry: &HitEntry) -> Value {
    json!({
        "ruleId": entry.rule_id,
        "listId": entry.list_id,
        "count": entry.count,
    })
}

fn handle_operation(request: &Value) -> Option<Value> {
    let op = request.get("op")?.as_str()?;
    let rule_id = request.get("ruleId").and_then(Value::as_i64);
    let list_id = request.get("listId").and_then(Value::as_i64);
    match op {
        "hit.increment" => {
            let amount = request
                .get("count")
                .and_then(Value::as_u64)
                .filter(|amount| *amount > 0)
                .unwrap_or(1);
            counters().increment_by(rule_id?, list_id, amount);
            Some(json!({ "ok": true }))
        }
        "hit.snapshot" => Some(json!({
            "items": counters().snapshot().iter().map(entry_json).collect::<Vec<_>>(),
        })),
        "hit.total" => Some(json!({ "total": counters().total() })),
        "hit.reset" => {
            counters().reset();
            Some(json!({ "ok": true }))
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
            let mut bytes = bytes;
            let length = bytes.len();
            let pointer = bytes.as_mut_ptr();
            std::mem::forget(bytes);
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
pub unsafe extern "C" fn diting_hit_core_call(
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

/// Payload layout version; the loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_hit_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill; release it with [`diting_hit_core_free`].
#[no_mangle]
pub extern "C" fn diting_hit_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_hit_core_alloc`] or a `_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_hit_core_free(pointer: *mut u8, size: usize) {
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
        assert!(handle_operation(&json!({ "op": "hit.increment" })).is_none());
    }

    #[test]
    fn increments_and_snapshots() {
        counters().reset();
        assert!(handle_operation(
            &json!({ "op": "hit.increment", "ruleId": 3, "listId": 4, "count": 2 })
        )
        .is_some());
        let answer = handle_operation(&json!({ "op": "hit.snapshot" })).expect("snapshot");
        let items = answer["items"].as_array().expect("items");
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["ruleId"], json!(3));
        assert_eq!(items[0]["listId"], json!(4));
        assert_eq!(items[0]["count"], json!(2));
        counters().reset();
    }
}
