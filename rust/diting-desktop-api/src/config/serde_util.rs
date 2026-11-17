//! Small serde helpers shared by the config models.
//!
//! Go's `encoding/json` treats JSON `null` as a zero value for every field type, while serde's
//! derived implementations reject `null` for `Vec`, maps and scalars. The helpers below restore
//! that tolerance for the collection fields used by the config model. They are only needed for
//! explicitly present `null` values: missing fields are filled by the container-level
//! `#[serde(default)]` from each struct's `Default`, which mirrors Go unmarshalling into
//! `DefaultConfig`.

use std::collections::HashMap;
use std::hash::Hash;

use serde::Deserialize;
use serde::Deserializer;

/// Deserialize a list, mapping `null` to an empty list.
pub fn nullable_vec<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    Ok(Option::<Vec<T>>::deserialize(deserializer)?.unwrap_or_default())
}

/// Deserialize a map, mapping `null` to an empty map.
pub fn nullable_map<'de, D, K, V>(deserializer: D) -> Result<HashMap<K, V>, D::Error>
where
    D: Deserializer<'de>,
    K: Deserialize<'de> + Eq + Hash,
    V: Deserialize<'de>,
{
    Ok(Option::<HashMap<K, V>>::deserialize(deserializer)?.unwrap_or_default())
}

/// `skip_serializing_if` for Go `omitempty` integer fields.
pub fn is_zero_i32(value: &i32) -> bool {
    *value == 0
}

/// `skip_serializing_if` for Go `omitempty` unsigned fields.
pub fn is_zero_u32(value: &u32) -> bool {
    *value == 0
}

/// `skip_serializing_if` for Go `omitempty` int64 fields.
pub fn is_zero_i64(value: &i64) -> bool {
    *value == 0
}

/// `skip_serializing_if` for Go `omitempty` float fields.
pub fn is_zero_f64(value: &f64) -> bool {
    *value == 0.0
}

/// `skip_serializing_if` for Go `omitempty` boolean fields.
pub fn is_false(value: &bool) -> bool {
    !*value
}
