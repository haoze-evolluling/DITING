//! Typed reads of the JSON payload. Missing and mistyped fields are `None`, never a guess: the
//! caller (Dart) owns the shapes and a payload that does not fit is rejected by `ffi`.

use serde_json::{Map, Value};
use std::sync::OnceLock;

fn empty() -> &'static Map<String, Value> {
    static EMPTY: OnceLock<Map<String, Value>> = OnceLock::new();
    EMPTY.get_or_init(Map::new)
}

/// The object at `value`, or a shared empty map when it is not one.
pub fn object(value: &Value) -> &Map<String, Value> {
    value.as_object().unwrap_or(empty())
}

/// The object stored under `key`, or a shared empty map.
pub fn child<'a>(value: &'a Value, key: &str) -> &'a Map<String, Value> {
    value.get(key).and_then(Value::as_object).unwrap_or(empty())
}

/// A string field; numbers and booleans are not coerced.
pub fn text(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
}

/// A string field, with `None` for a missing field and `Some("")` for `null`.
pub fn text_or_empty(value: &Value, key: &str) -> String {
    text(value, key).unwrap_or_default()
}

/// An integer field; `1.0` is accepted because SQLite may hand back a float.
pub fn integer(value: &Value, key: &str) -> Option<i64> {
    let field = value.get(key)?;
    if let Some(number) = field.as_i64() {
        return Some(number);
    }
    field.as_f64().map(|number| number.trunc() as i64)
}

/// An integer field with a default; a missing, null or mistyped field uses `fallback`.
pub fn integer_or(value: &Value, key: &str, fallback: i64) -> i64 {
    integer(value, key).unwrap_or(fallback)
}

/// SQLite flags: `true`/`false` or a non-zero number.
pub fn flag(value: Option<&Value>) -> Option<bool> {
    match value? {
        Value::Bool(flag) => Some(*flag),
        Value::Number(number) => Some(number.as_f64().is_some_and(|v| v != 0.0)),
        _ => None,
    }
}

/// The flag at `key`, with a default for a missing or mistyped field.
pub fn flag_or(value: &Value, key: &str, fallback: bool) -> bool {
    flag(value.get(key)).unwrap_or(fallback)
}

/// Every value of an array, or an empty slice.
pub fn list<'a>(value: &'a Value, key: &str) -> &'a [Value] {
    value
        .get(key)
        .and_then(Value::as_array)
        .map_or(&[], Vec::as_slice)
}

/// A nullable string: `null`/missing becomes `Value::Null`.
pub fn nullable_text(value: Option<&Value>) -> Value {
    value
        .filter(|field| !field.is_null())
        .cloned()
        .unwrap_or(Value::Null)
}
