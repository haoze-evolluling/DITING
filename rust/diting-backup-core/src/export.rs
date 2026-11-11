//! Document writer: the app hands over a snapshot of its settings and rows, this crate decides
//! what a backup of the selected groups looks like.
//!
//! Input  `{nowMs, groups: [key], fields: {<key>: <snapshot>}}`
//! Output `{content, included: [key], counts: {key: n}, skipped: [{group, reason}]}`
//!
//! `content` is the whole file text (`{format, version, exportedAt, data, selection}`); the file
//! name stays in the app because it is a local-time stamp.

use serde_json::{json, Map, Value};

use crate::groups::{ordered_keys, skip_entry, Group, ORDER};
use crate::value::{as_object, get, integer};

mod values;

/// Highest document version this build writes and the highest it accepts.
pub const FORMAT: &str = "diting-backup";
pub const VERSION: i64 = 2;

pub fn run(input: &Value) -> Value {
    let now = integer(input, "nowMs").unwrap_or(0);
    let requested: Vec<String> = get(input, "groups")
        .and_then(Value::as_array)
        .map(|keys| {
            keys.iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    let fields = get(input, "fields").cloned().unwrap_or(Value::Null);
    let wanted = ordered_keys(&requested);

    let mut data = Map::new();
    let mut counts = Map::new();
    let mut included = Vec::new();
    let mut skipped = Vec::new();

    for group in ORDER {
        if !wanted.contains(&group) {
            continue;
        }
        let source = get(&fields, group.key()).cloned().unwrap_or(Value::Null);
        match values::build(group, &source) {
            Ok(value) => {
                counts.insert(String::from(group.key()), json!(count_of(&value)));
                data.insert(String::from(group.key()), value);
                included.push(Value::String(String::from(group.key())));
            }
            // A group whose local snapshot cannot be read is reported, not silently dropped: the
            // user has to know the file is missing that group.
            Err(reason) => skipped.push(skip_entry(group, reason)),
        }
    }

    let selection: Vec<&Value> = included.iter().collect();
    let document = json!({
        "format": FORMAT,
        "version": VERSION,
        "exportedAt": now,
        "data": Value::Object(data),
        "selection": selection,
    });

    json!({
        "content": serialize(&document),
        "included": included,
        "counts": Value::Object(counts),
        "skipped": skipped,
    })
}

/// Indented like `JsonEncoder.withIndent('  ')`; the file is meant to be readable and diffable.
pub fn serialize(document: &Value) -> String {
    let mut text = serde_json::to_string_pretty(document).unwrap_or_default();
    text.push('\n');
    text
}

/// `null` → 0, list/map → their length, anything else → 1 (the "result" column of the export
/// summary tells the user how much of each group landed in the file).
fn count_of(value: &Value) -> u64 {
    match value {
        Value::Null => 0,
        Value::Array(items) => items.len() as u64,
        Value::Object(record) => record.len() as u64,
        _ => 1,
    }
}

/// Reads `{format, version}` and says why a file is not ours; used by the importer.
pub fn check_envelope(text: &str) -> Result<Map<String, Value>, Envelope> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err(Envelope::Empty);
    }
    let parsed: Value = serde_json::from_str(trimmed).map_err(|_| Envelope::NotJson)?;
    let record = as_object(&parsed).ok_or(Envelope::RootNotObject)?.clone();
    if record.get("format").and_then(Value::as_str) != Some(FORMAT) {
        return Err(Envelope::NotBackup);
    }
    match record.get("version") {
        None => Err(Envelope::NoVersion),
        Some(Value::Number(number)) => {
            let version = number.as_i64().unwrap_or(VERSION);
            if version > VERSION {
                Err(Envelope::TooNew(version))
            } else if version < 1 {
                Err(Envelope::NotBackup)
            } else if !matches!(record.get("data"), Some(Value::Object(_))) {
                Err(Envelope::NoData)
            } else {
                Ok(record)
            }
        }
        Some(_) => Err(Envelope::NotBackup),
    }
}

/// Why a file cannot be imported at all (a fatal error, not a per-group one).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Envelope {
    Empty,
    NotJson,
    RootNotObject,
    NotBackup,
    NoVersion,
    TooNew(i64),
    NoData,
}

impl Envelope {
    pub fn kind(self) -> &'static str {
        match self {
            Envelope::Empty => "empty",
            Envelope::NotJson => "notJson",
            Envelope::RootNotObject => "rootNotObject",
            Envelope::NotBackup => "notBackup",
            Envelope::NoVersion => "noVersion",
            Envelope::TooNew(_) => "tooNew",
            Envelope::NoData => "noData",
        }
    }

    pub fn detail(self) -> Option<i64> {
        match self {
            Envelope::TooNew(version) => Some(version),
            _ => None,
        }
    }
}

/// Groups present in `data`, in declaration order (the exporter's own order is trusted only as a
/// hint; an edited file may list them any way it likes).
pub fn present_groups(data: &Map<String, Value>) -> Vec<Group> {
    let keys: Vec<String> = data.keys().cloned().collect();
    ordered_keys(&keys)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_rules() {
        assert_eq!(check_envelope("  ").unwrap_err(), Envelope::Empty);
        assert_eq!(check_envelope("hello").unwrap_err(), Envelope::NotJson);
        assert_eq!(check_envelope("[]").unwrap_err(), Envelope::RootNotObject);
        assert_eq!(
            check_envelope("{\"foo\":1}").unwrap_err(),
            Envelope::NotBackup
        );
        // A 1.4.3 flat file has no `format` at all.
        assert_eq!(
            check_envelope("{\"formatVersion\":10}").unwrap_err(),
            Envelope::NotBackup
        );
        assert_eq!(
            check_envelope("{\"format\":\"diting-backup\",\"version\":99,\"data\":{}}")
                .unwrap_err(),
            Envelope::TooNew(99)
        );
        assert_eq!(
            check_envelope("{\"format\":\"diting-backup\",\"data\":{}}").unwrap_err(),
            Envelope::NoVersion
        );
        assert_eq!(
            check_envelope("{\"format\":\"diting-backup\",\"version\":1}").unwrap_err(),
            Envelope::NoData
        );
        // Version 1 group files still import.
        assert!(check_envelope("{\"format\":\"diting-backup\",\"version\":1,\"data\":{}}").is_ok());
    }

    #[test]
    fn counts_match_the_shape_of_a_group() {
        assert_eq!(count_of(&Value::Null), 0);
        assert_eq!(count_of(&json!([1, 2, 3])), 3);
        assert_eq!(count_of(&json!({"a": 1})), 1);
        assert_eq!(count_of(&json!("x")), 1);
    }

    #[test]
    fn an_empty_selection_still_produces_a_valid_document() {
        let output = run(&json!({"nowMs": 7, "groups": [], "fields": {}}));
        let document: Value =
            serde_json::from_str(output["content"].as_str().unwrap()).expect("valid json");
        assert_eq!(document["version"], json!(VERSION));
        assert_eq!(document["exportedAt"], json!(7));
        assert_eq!(document["data"], json!({}));
        assert_eq!(document["selection"], json!([]));
    }
}
