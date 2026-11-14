//! Typed reads of the JSON payload. Missing and mistyped fields are `None`, never a guess: the
//! caller owns the shapes and a payload that does not fit is rejected by [`crate::schedule`].

use serde_json::Value;

/// A string field; numbers and booleans are not coerced.
pub fn text(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
}

/// An integer field; `1.0` is accepted because a JSON encoder may hand back a float.
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

/// Every value of an array, or an empty slice.
pub fn list<'a>(value: &'a Value, key: &str) -> &'a [Value] {
    value
        .get(key)
        .and_then(Value::as_array)
        .map_or(&[], Vec::as_slice)
}
