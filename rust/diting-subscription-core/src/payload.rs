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

pub fn integer(value: &Value, key: &str) -> Option<i64> {
    let field = value.get(key)?;
    if let Some(number) = field.as_i64() {
        return Some(number);
    }
    field.as_f64().map(|number| number.trunc() as i64)
}

pub fn integer_or(value: &Value, key: &str, fallback: i64) -> i64 {
    integer(value, key).unwrap_or(fallback)
}

pub fn flag(value: Option<&Value>) -> Option<bool> {
    match value? {
        Value::Bool(flag) => Some(*flag),
        Value::Number(number) => Some(number.as_f64().is_some_and(|v| v != 0.0)),
        _ => None,
    }
}

pub fn flag_or(value: &Value, key: &str, fallback: bool) -> bool {
    flag(value.get(key)).unwrap_or(fallback)
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
