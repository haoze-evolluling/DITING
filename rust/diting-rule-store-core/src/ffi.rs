//! C ABI for the `dart:ffi` caller.
//!
//! Two entries: `rows` (a page of joined rows to rules) and `plan` (statements and predicates).
//! Payloads are JSON; the header stays fixed — `magic "DRS1" | abi` — so the Dart loader refuses a
//! library whose version does not match what it was compiled against.

use serde_json::{json, Value};

use crate::identity::{identity, parse_flavor, predicate, rewrite_target_type};
use crate::import::{
    import_plan, page_query, remove_source_plan, set_source_enabled_plan, summary, tables_plan,
};
use crate::probe::{flag, integer, list, text};
use crate::rows::{rule_from_joined, rule_from_sources, subscriptions};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DRS1");

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

/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload.
unsafe fn call(
    text: *const u8,
    len: usize,
    handler: fn(&Value) -> Option<Value>,
) -> Option<Vec<u8>> {
    let request: Value = serde_json::from_slice(input_at(text, len)).ok()?;
    Some(payload(handler(&request)?))
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_rule_store_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill; release it with
/// [`diting_rule_store_core_free`].
#[no_mangle]
pub extern "C" fn diting_rule_store_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// # Safety
/// `pointer`/`size` must come from [`diting_rule_store_core_alloc`] or a `_core_*` entry.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_store_core_free(pointer: *mut u8, size: usize) {
    if pointer.is_null() || size == 0 {
        return;
    }
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, size,
    )));
}

/// Maps one page of rows to rules. In: `{kind, subscriptions, joined}` (a joined query) or
/// `{kind, subscriptions, rules, sources}` (rules loaded for one app).
///
/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_store_core_rows(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    respond(call(text, len, rows), out_len)
}

/// Statement and predicate plans. In: `{op: ...}` (see [`plan`]).
///
/// # Safety
/// `text`/`len` must describe one readable UTF-8 JSON payload; `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_rule_store_core_plan(
    text: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    respond(call(text, len, plan), out_len)
}

fn rows(request: &Value) -> Option<Value> {
    let kind = text(request, "kind").unwrap_or_else(|| String::from("block"));
    let names = subscriptions(request);
    let joined = list(request, "joined");
    let rules = if !joined.is_empty() {
        rule_from_joined(&kind, joined, &names)
    } else {
        rule_from_sources(
            &kind,
            list(request, "rules"),
            list(request, "sources"),
            &names,
        )
    };
    Some(json!({"rules": rules}))
}

fn plan(request: &Value) -> Option<Value> {
    let operation = text(request, "op").unwrap_or_default();
    Some(match operation.as_str() {
        "import" => {
            let parsed = crate::probe::get(request, "parsed")?;
            let plan = import_plan(
                parsed,
                &text(request, "source").unwrap_or_default(),
                &text(request, "kind").unwrap_or_else(|| String::from("domain")),
                flag(request, "enabled").unwrap_or(true),
                integer(request, "chunkSize").unwrap_or(1000).max(1) as usize,
                integer(request, "nowMs").unwrap_or_default(),
            );
            json!({"batches": plan.batches, "summary": summary(&plan, parsed)})
        }
        "removeSource" => remove_source_plan(&text(request, "source").unwrap_or_default()),
        "setSourceEnabled" => set_source_enabled_plan(
            &text(request, "source").unwrap_or_default(),
            flag(request, "enabled").unwrap_or(false),
        ),
        "identity" => {
            let rule = crate::probe::get(request, "rule")?;
            let package = text(request, "package");
            let kind = text(request, "kind").unwrap_or_else(|| String::from("block"));
            let built = identity(
                &kind,
                parse_flavor(&text(request, "flavor").unwrap_or_default()),
                rule,
                package.as_deref(),
                integer(request, "nowMs").unwrap_or_default(),
            );
            json!({
                "table": built.table,
                "sourceTable": built.source_table,
                "targetType": built.target_type.as_str(),
                "where": built.where_sql,
                "args": built.args,
                "row": Value::Object(built.row),
            })
        }
        "pageQuery" => page_query(
            &text(request, "kind").unwrap_or_else(|| String::from("block")),
            integer(request, "beforeId"),
            integer(request, "limit"),
        ),
        "predicate" => {
            let (where_sql, args) = predicate(
                &text(request, "name").unwrap_or_default(),
                &text(request, "package").unwrap_or_default(),
            );
            json!({"where": where_sql, "args": args})
        }
        "tables" => tables_plan(),
        "targetType" => json!({
            "type": rewrite_target_type(text(request, "target").as_deref()).as_str(),
        }),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_carries_magic_and_version() {
        let bytes = header();
        assert_eq!(&bytes[0..4], b"DRS1");
        assert_eq!(
            u32::from_le_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]),
            ABI_VERSION
        );
    }

    #[test]
    fn an_unknown_operation_is_rejected() {
        let request = b"{\"op\":\"nope\"}";
        let mut length = 3usize;
        let pointer =
            unsafe { diting_rule_store_core_plan(request.as_ptr(), request.len(), &mut length) };
        assert!(pointer.is_null());
        assert_eq!(length, 0);
    }

    #[test]
    fn rows_round_trip_through_the_boundary() {
        let request = json!({
            "kind": "block",
            "subscriptions": [{"id": 4, "name": "订阅A"}],
            "joined": [
                {"id": 9, "pattern": "a.test", "enabled": 1, "important": 0,
                 "sourceName": "sub_4", "sourceEnabled": 1},
                {"id": 9, "pattern": "a.test", "enabled": 1, "important": 0,
                 "sourceName": "useradd", "sourceEnabled": 1},
            ],
        })
        .to_string();
        let mut length = 0usize;
        let pointer =
            unsafe { diting_rule_store_core_rows(request.as_ptr(), request.len(), &mut length) };
        assert!(!pointer.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(pointer, length) }.to_vec();
        unsafe { diting_rule_store_core_free(pointer, length) };
        let answer: Value = serde_json::from_slice(&bytes[8..]).expect("json");
        assert_eq!(answer["rules"][0]["subscriptionName"], json!("订阅A"));
        assert_eq!(answer["rules"][0]["source"], json!("subscription"));
    }

    #[test]
    fn target_type_is_reported_for_a_single_target() {
        for (target, expected) in [
            ("1.1.1.1", "IPv4"),
            ("::1", "IPv6"),
            ("a.test", "CNAME"),
            ("", "CNAME"),
        ] {
            let request = json!({"op": "targetType", "target": target}).to_string();
            let mut length = 0usize;
            let pointer = unsafe {
                diting_rule_store_core_plan(request.as_ptr(), request.len(), &mut length)
            };
            let bytes = unsafe { std::slice::from_raw_parts(pointer, length) }.to_vec();
            unsafe { diting_rule_store_core_free(pointer, length) };
            let answer: Value = serde_json::from_slice(&bytes[8..]).expect("json");
            assert_eq!(answer["type"], json!(expected), "target {target}");
        }
    }
}
