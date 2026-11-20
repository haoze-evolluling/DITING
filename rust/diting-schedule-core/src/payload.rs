use serde_json::Value;

pub fn text(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
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

pub fn list<'a>(value: &'a Value, key: &str) -> &'a [Value] {
    value
        .get(key)
        .and_then(Value::as_array)
        .map_or(&[], Vec::as_slice)
}
