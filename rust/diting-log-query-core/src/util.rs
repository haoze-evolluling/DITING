//! Small JSON accessors over the payload maps; every aggregate reads through these.

use std::cmp::Ordering;

use serde_json::{Map, Value};

use crate::payload;

pub(crate) fn i(map: &Map<String, Value>, key: &str) -> i64 {
    payload::integer_in(map, key).unwrap_or(0)
}

pub(crate) fn n(map: &Map<String, Value>, key: &str) -> f64 {
    payload::number(&Value::Object(map.clone()), key).unwrap_or(0.0)
}

pub(crate) fn s(map: &Map<String, Value>, key: &str) -> String {
    payload::text_in_or_empty(map, key)
}

pub(crate) fn b(map: &Map<String, Value>, key: &str) -> bool {
    map.get(key).and_then(Value::as_bool).unwrap_or_default()
}

pub(crate) fn child<'a>(request: &'a Value, key: &str) -> &'a Map<String, Value> {
    payload::child(request, key)
}

pub(crate) fn items<'a>(value: &'a Value, key: &str) -> Vec<&'a Map<String, Value>> {
    payload::list(value, key)
        .iter()
        .map(payload::object)
        .collect()
}

pub(crate) fn names(request: &Value) -> &Map<String, Value> {
    child(request, "names")
}

pub(crate) fn resolved_name(request: &Value, id: &str) -> String {
    payload::text_in_or_empty(names(request), id)
}

/// Dart's `String.compareTo` compares UTF-16 code units, which differs from Rust's byte order for
/// characters outside the BMP.
pub(crate) fn dart_cmp(left: &str, right: &str) -> Ordering {
    left.encode_utf16().cmp(right.encode_utf16())
}

pub(crate) fn percent(part: i64, total: i64) -> f64 {
    if total == 0 {
        0.0
    } else {
        part as f64 / total as f64
    }
}
