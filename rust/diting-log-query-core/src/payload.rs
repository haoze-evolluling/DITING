//! Typed reads of the JSON payload. Missing and mistyped fields are `None`, never a guess.

use serde_json::{Map, Value};
use std::sync::OnceLock;

fn empty() -> &'static Map<String, Value> {
    static EMPTY: OnceLock<Map<String, Value>> = OnceLock::new();
    EMPTY.get_or_init(Map::new)
}

pub fn object(value: &Value) -> &Map<String, Value> {
    value.as_object().unwrap_or(empty())
}

pub fn child<'a>(value: &'a Value, key: &str) -> &'a Map<String, Value> {
    value.get(key).and_then(Value::as_object).unwrap_or(empty())
}

pub fn text(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
}

pub fn text_or_empty(value: &Value, key: &str) -> String {
    text(value, key).unwrap_or_default()
}

pub fn text_in(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key).and_then(Value::as_str).map(str::to_owned)
}

pub fn text_in_or_empty(map: &Map<String, Value>, key: &str) -> String {
    text_in(map, key).unwrap_or_default()
}

pub fn integer(value: &Value, key: &str) -> Option<i64> {
    let field = value.get(key)?;
    if let Some(number) = field.as_i64() {
        return Some(number);
    }
    field.as_f64().map(|number| number.trunc() as i64)
}

pub fn integer_in(map: &Map<String, Value>, key: &str) -> Option<i64> {
    let field = map.get(key)?;
    if let Some(number) = field.as_i64() {
        return Some(number);
    }
    field.as_f64().map(|number| number.trunc() as i64)
}

pub fn integer_or(value: &Value, key: &str, fallback: i64) -> i64 {
    integer(value, key).unwrap_or(fallback)
}

pub fn flag_or(value: &Value, key: &str, fallback: bool) -> bool {
    match value.get(key) {
        Some(Value::Bool(flag)) => *flag,
        Some(Value::Number(number)) => number.as_f64().is_some_and(|v| v != 0.0),
        _ => fallback,
    }
}

pub fn list<'a>(value: &'a Value, key: &str) -> &'a [Value] {
    value
        .get(key)
        .and_then(Value::as_array)
        .map_or(&[], Vec::as_slice)
}

pub fn nullable_text(value: Option<&Value>) -> Value {
    value
        .filter(|field| !field.is_null())
        .cloned()
        .unwrap_or(Value::Null)
}

/// A double field; integer JSON numbers are promoted.
pub fn number(value: &Value, key: &str) -> Option<f64> {
    value.get(key).and_then(Value::as_f64)
}
