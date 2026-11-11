//! Typed reads of the JSON payload.
//!
//! The payloads describe database rows, so a column of the wrong type is "absent" rather than an
//! error: a legacy database may hold a `NULL` where the app expects an integer, and the mapping has
//! always tolerated that.

use serde_json::{Map, Value};

pub fn get<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    value.as_object().and_then(|record| record.get(key))
}

pub fn text(value: &Value, key: &str) -> Option<String> {
    get(value, key).and_then(Value::as_str).map(str::to_string)
}

/// `1`/`0` column to a bool; anything else is `None`.
pub fn flag(value: &Value, key: &str) -> Option<bool> {
    match get(value, key) {
        Some(Value::Bool(flag)) => Some(*flag),
        Some(Value::Number(number)) => number.as_i64().map(|flag| flag != 0),
        _ => None,
    }
}

pub fn integer(value: &Value, key: &str) -> Option<i64> {
    get(value, key).and_then(Value::as_i64)
}

pub fn list<'a>(value: &'a Value, key: &str) -> &'a [Value] {
    match get(value, key) {
        Some(Value::Array(items)) => items,
        _ => &[],
    }
}

pub fn record(value: &Value) -> Option<&Map<String, Value>> {
    value.as_object()
}

pub fn strings(items: &[Value]) -> Vec<String> {
    items
        .iter()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect()
}
