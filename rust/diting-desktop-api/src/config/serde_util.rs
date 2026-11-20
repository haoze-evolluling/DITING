use std::collections::HashMap;
use std::hash::Hash;

use serde::Deserialize;
use serde::Deserializer;

pub fn nullable_vec<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    Ok(Option::<Vec<T>>::deserialize(deserializer)?.unwrap_or_default())
}

pub fn nullable_map<'de, D, K, V>(deserializer: D) -> Result<HashMap<K, V>, D::Error>
where
    D: Deserializer<'de>,
    K: Deserialize<'de> + Eq + Hash,
    V: Deserialize<'de>,
{
    Ok(Option::<HashMap<K, V>>::deserialize(deserializer)?.unwrap_or_default())
}

pub fn is_zero_i32(value: &i32) -> bool {
    *value == 0
}

pub fn is_zero_u32(value: &u32) -> bool {
    *value == 0
}

pub fn is_zero_i64(value: &i64) -> bool {
    *value == 0
}

pub fn is_zero_f64(value: &f64) -> bool {
    *value == 0.0
}

pub fn is_false(value: &bool) -> bool {
    !*value
}
