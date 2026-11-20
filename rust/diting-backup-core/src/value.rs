use std::collections::BTreeMap;

use serde_json::{Map, Value};

pub fn object() -> Map<String, Value> {
    Map::new()
}

pub fn as_object(value: &Value) -> Option<&Map<String, Value>> {
    value.as_object()
}

pub fn get<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    value.as_object().and_then(|record| record.get(key))
}

pub fn text(value: &Value, key: &str) -> Option<String> {
    get(value, key).and_then(Value::as_str).map(str::to_string)
}

pub fn trimmed(value: &Value, key: &str) -> Option<String> {
    get(value, key).and_then(Value::as_str).and_then(|text| {
        let trimmed = text.trim();
        (!trimmed.is_empty()).then(|| trimmed.to_string())
    })
}

pub fn boolean(value: &Value, key: &str) -> Option<bool> {
    get(value, key).and_then(Value::as_bool)
}

pub fn truthy(value: &Value, key: &str) -> Option<bool> {
    match get(value, key) {
        Some(Value::Bool(flag)) => Some(*flag),
        Some(Value::Number(number)) => number.as_i64().map(|flag| flag != 0),
        _ => None,
    }
}

pub fn integer(value: &Value, key: &str) -> Option<i64> {
    get(value, key).and_then(Value::as_i64)
}

pub fn number(value: &Value, key: &str) -> Option<f64> {
    get(value, key).and_then(Value::as_f64)
}

pub fn list<'a>(value: &'a Value, key: &str) -> Option<&'a Vec<Value>> {
    get(value, key).and_then(Value::as_array)
}

pub fn array(value: &Value, key: &str) -> Vec<Value> {
    list(value, key).cloned().unwrap_or_default()
}

pub fn sorted_strings(value: &Value) -> Vec<Value> {
    string_set(value).into_keys().map(Value::String).collect()
}

pub fn string_set(value: &Value) -> BTreeMap<String, ()> {
    let mut set = BTreeMap::new();
    match value {
        Value::Array(items) => {
            for item in items {
                if let Value::String(text) = item {
                    let trimmed = text.trim();
                    if !trimmed.is_empty() {
                        set.insert(trimmed.to_string(), ());
                    }
                }
            }
        }
        Value::Object(record) => {
            for key in record.keys() {
                let trimmed = key.trim();
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_string(), ());
                }
            }
        }
        _ => {}
    }
    set
}

pub fn set_of_strings(values: &[String]) -> BTreeMap<String, ()> {
    values
        .iter()
        .map(|value| (value.clone(), ()))
        .collect::<BTreeMap<_, _>>()
}

pub fn same_string_set(left: &Value, right: &Value) -> bool {
    string_set(left) == string_set(right)
}

pub fn encode_json(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| String::from("null"))
}

pub fn config_signature(value: &Value) -> String {
    let mut entries: Vec<(String, Value)> = match value {
        Value::Object(record) => record
            .iter()
            .filter(|(key, _)| key.as_str() != "id")
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect(),
        other => return flat_signature(other),
    };
    entries.sort_by(|left, right| left.0.cmp(&right.0));
    let body: Vec<String> = entries
        .into_iter()
        .map(|(key, value)| format!("{key}:{}", flat_signature(&value)))
        .collect();
    format!("{{{}}}", body.join(","))
}

fn flat_signature(value: &Value) -> String {
    match value {
        Value::Object(record) => {
            let mut entries: Vec<(&String, &Value)> = record.iter().collect();
            entries.sort_by(|left, right| left.0.cmp(right.0));
            let body: Vec<String> = entries
                .into_iter()
                .map(|(key, value)| format!("{key}:{}", flat_signature(value)))
                .collect();
            format!("{{{}}}", body.join(","))
        }
        Value::Array(items) => {
            let body: Vec<String> = items.iter().map(flat_signature).collect();
            format!("[{}]", body.join(","))
        }
        Value::String(text) => text.clone(),
        other => other.to_string(),
    }
}

pub fn slug_of(value: &str) -> String {
    let mut output = String::new();
    for unit in value.trim().to_lowercase().encode_utf16() {
        let character = char::from_u32(u32::from(unit)).unwrap_or('\u{FFFD}');
        if character.is_ascii_lowercase() || character.is_ascii_digit() {
            output.push(character);
        } else {
            output.push('_');
        }
    }
    if output.is_empty() {
        String::from("provider")
    } else {
        output
    }
}

pub fn decimal(value: &Value, key: &str) -> Option<f64> {
    match get(value, key) {
        Some(Value::Number(number)) => number.as_f64().map(|value| value.clamp(0.0, 1.0)),
        Some(Value::String(text)) => text.parse::<f64>().ok().map(|value| value.clamp(0.0, 1.0)),
        _ => None,
    }
}

pub fn round_opacity(value: f64) -> Value {
    let rounded = (value * 100.0).round() / 100.0;
    Value::from(rounded)
}

pub fn i64_value(value: i64) -> Value {
    Value::from(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn typed_probes_treat_wrong_types_as_absent() {
        let value = json!({"text": "  x  ", "flag": true, "count": 3, "list": ["a", " " ]});
        assert_eq!(trimmed(&value, "text").as_deref(), Some("x"));
        assert_eq!(boolean(&value, "flag"), Some(true));
        assert_eq!(integer(&value, "count"), Some(3));
        assert_eq!(integer(&value, "text"), None);
        assert_eq!(text(&value, "missing"), None);
        assert_eq!(sorted_strings(&value["list"]), vec![json!("a")]);
    }

    #[test]
    fn string_sets_fold_lists_and_object_keys() {
        assert_eq!(string_set(&json!(["b", " a ", "b"])).len(), 2);
        assert_eq!(string_set(&json!({"b": 1, "a": 2})).len(), 2);
        assert_eq!(string_set(&json!("nope")).len(), 0);
        assert!(same_string_set(
            &json!(["a", "b"]),
            &json!({"b": 1, "a": 2})
        ));
    }

    #[test]
    fn config_signature_ignores_ids_and_key_order() {
        let left = json!({"id": "user_1", "name": "A", "port": 853});
        let right = json!({"port": 853, "name": "A", "id": "other"});
        assert_eq!(config_signature(&left), config_signature(&right));
        assert_ne!(
            config_signature(&left),
            config_signature(&json!({"id": "user_1", "name": "B", "port": 853}))
        );
    }

    #[test]
    fn slugs_and_opacity() {
        assert_eq!(slug_of(" 我的 DoH "), "___doh");
        assert_eq!(slug_of("My DoH 1"), "my_doh_1");
        assert_eq!(slug_of("   "), "provider");
        assert_eq!(round_opacity(0.800000011920929), json!(0.8));
        assert_eq!(decimal(&json!({"v": "1.4"}), "v"), Some(1.0));
        assert_eq!(decimal(&json!({"v": true}), "v"), None);
    }
}
