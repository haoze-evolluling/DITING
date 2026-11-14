//! The C ABI the JNI/FFI caller loads. A handle owns one [`FlowTable`]; snapshots are JSON with the
//! fixed `magic "DFL1" | abi` header so a loader refuses a mismatched library.

use std::slice;

use serde_json::Value;

use crate::payload;
use crate::session::FlowTable;

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DFL1");

fn into_buffer(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (pointer, length)
}

/// # Safety
/// `out_len` must be writable; `bytes` is `None` (reported as null) or a finished buffer whose
/// ownership moves to the caller.
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

#[no_mangle]
pub extern "C" fn diting_flow_abi_version() -> u32 {
    ABI_VERSION
}

/// Creates a session table. `capacity == 0` selects the default.
#[no_mangle]
pub extern "C" fn diting_flow_new(capacity: usize) -> *mut FlowTable {
    Box::into_raw(Box::new(FlowTable::new(capacity)))
}

/// Drops a handle created by [`diting_flow_new`].
///
/// # Safety
/// `handle` must come from [`diting_flow_new`] and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_flow_free(handle: *mut FlowTable) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Records one flow event from a JSON payload. Returns 0 on success, -1 on a bad payload, -2 on a
/// null handle (treated as "flow view disabled").
///
/// # Safety
/// `handle` must be valid; `text`/`len` must describe one readable JSON payload.
#[no_mangle]
pub unsafe extern "C" fn diting_flow_record(
    handle: *mut FlowTable,
    text: *const u8,
    len: usize,
) -> i32 {
    let Some(table) = handle.as_mut() else {
        return -2;
    };
    let Ok(request) = serde_json::from_slice::<Value>(input_at(text, len)) else {
        return -1;
    };
    let Some(event) = payload::decode_event(&request) else {
        return -1;
    };
    table.record(event);
    0
}

/// Empties the table.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn diting_flow_reset(handle: *mut FlowTable) -> u32 {
    if let Some(table) = handle.as_mut() {
        table.reset();
    }
    0
}

/// Current row count.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn diting_flow_len(handle: *const FlowTable) -> usize {
    handle.as_ref().map_or(0, FlowTable::len)
}

/// Returns an incremental snapshot for `{ "sinceSeq": u64, "limit": n }` as `DFL1 | abi | json`.
///
/// # Safety
/// `handle` must be valid; `text`/`len` must describe one readable JSON payload; `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn diting_flow_snapshot(
    handle: *const FlowTable,
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let Some(table) = handle.as_ref() else {
        return respond(None, out_len);
    };
    let Ok(request) = serde_json::from_slice::<Value>(input_at(text, len)) else {
        return respond(None, out_len);
    };
    let json = table
        .snapshot(payload::since_seq(&request), payload::limit(&request))
        .to_json();
    let mut bytes = Vec::with_capacity(8 + json.len());
    bytes.extend_from_slice(&MAGIC.to_le_bytes());
    bytes.extend_from_slice(&ABI_VERSION.to_le_bytes());
    bytes.extend_from_slice(json.as_bytes());
    respond(Some(bytes), out_len)
}

/// Releases a buffer returned by [`diting_flow_snapshot`].
///
/// # Safety
/// `pointer`/`size` must come from [`diting_flow_snapshot`].
#[no_mangle]
pub unsafe extern "C" fn diting_flow_free_bytes(pointer: *mut u8, size: usize) {
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

    fn snapshot(handle: *const FlowTable, since: u64) -> Value {
        let request = format!("{{\"sinceSeq\":{since},\"limit\":0}}");
        let mut out_len = 0usize;
        let pointer = unsafe {
            diting_flow_snapshot(handle, request.as_ptr(), request.len(), &mut out_len)
        };
        assert!(!pointer.is_null());
        let bytes = unsafe { slice::from_raw_parts(pointer, out_len) };
        assert_eq!(&bytes[0..4], b"DFL1");
        let value: Value = serde_json::from_slice(&bytes[8..]).unwrap();
        unsafe { diting_flow_free_bytes(pointer, out_len) };
        value
    }

    #[test]
    fn ffi_round_trip_records_and_snapshots() {
        let handle = diting_flow_new(16);
        let event = r#"{"key":{"protocol":"tcp","srcIp":"10.0.0.2","srcPort":40000,
            "dstIp":"1.1.1.1","dstPort":443,"uid":9},"domain":"a.com","package":"com.a",
            "upDelta":10,"downDelta":20,"status":"active","atMs":5}"#;
        let rc = unsafe { diting_flow_record(handle, event.as_ptr(), event.len()) };
        assert_eq!(rc, 0);
        let value = snapshot(handle, 0);
        assert_eq!(value["sessions"][0]["dstIp"], "1.1.1.1");
        assert_eq!(value["sessions"][0]["downBytes"], 20);
        unsafe { diting_flow_free(handle) };
    }

    #[test]
    fn bad_payload_is_rejected() {
        let handle = diting_flow_new(4);
        let bad = b"not json";
        let rc = unsafe { diting_flow_record(handle, bad.as_ptr(), bad.len()) };
        assert_eq!(rc, -1);
        unsafe { diting_flow_free(handle) };
    }
}
