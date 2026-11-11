//! Subscription rows and the two edit forms. Column defaults and the storage spellings are
//! persisted, so they are pinned here: `sqflite` only reads and writes what this module decides.

use serde_json::{json, Value};

use crate::payload;
use crate::url::{self, UrlParts};

/// `SubscriptionSourceType.fromStorage`: only the exact `local` spelling is local.
pub fn source_type(value: Option<&str>) -> &'static str {
    if value == Some("local") {
        "local"
    } else {
        "remote"
    }
}

/// `SubscriptionKind.normalize`: trimmed, lower-cased `hosts` wins; everything else is `domain`.
pub fn kind(value: Option<&str>) -> &'static str {
    match value.map(|value| value.trim().to_lowercase()).as_deref() {
        Some("hosts") => "hosts",
        _ => "domain",
    }
}

/// `SubscriptionImportState.fromStorage`.
pub fn import_state(value: Option<&str>) -> &'static str {
    match value {
        Some("importing") => "importing",
        Some("failed") => "failed",
        _ => "ready",
    }
}

/// `SubscriptionAutoUpdateStatus.fromStorage`.
pub fn auto_update_status(value: Option<&str>) -> &'static str {
    match value {
        Some("success") => "success",
        Some("failed") => "failed",
        _ => "pending_retry",
    }
}

fn optional_text(row: &Value, key: &str) -> Value {
    payload::nullable_text(row.get(key))
}

fn optional_integer(row: &Value, key: &str) -> Value {
    payload::integer(row, key).map_or(Value::Null, Value::from)
}

/// One `subscription` row. Flags are INTEGER 0/1 in SQLite; `enabled` and `mirrorFallback` are
/// `true` when the column is missing or mistyped, matching the legacy reader.
pub fn record_from_row(row: &Value) -> Value {
    let source = source_type(row.get("sourceType").and_then(Value::as_str));
    json!({
        "id": payload::integer_or(row, "id", 0),
        "url": payload::text_or_empty(row, "url"),
        "name": payload::text_or_empty(row, "name"),
        "sourceType": source,
        "kind": kind(row.get("kind").and_then(Value::as_str)),
        "enabled": payload::flag_or(row, "enabled", true),
        "ruleCount": payload::integer_or(row, "ruleCount", 0),
        "lastUpdated": payload::integer_or(row, "lastUpdated", 0),
        "addedAt": payload::integer_or(row, "addedAt", 0),
        "importState": import_state(row.get("importState").and_then(Value::as_str)),
        "importError": optional_text(row, "importError"),
        "httpEtag": optional_text(row, "httpEtag"),
        "httpLastModified": optional_text(row, "httpLastModified"),
        "ruleSetHash": optional_text(row, "ruleSetHash"),
        "lastAttemptAt": payload::integer_or(row, "lastAttemptAt", 0),
        "consecutiveFailureCount": payload::integer_or(row, "consecutiveFailureCount", 0),
        "mirrorTemplate": optional_text(row, "mirrorTemplate"),
        "mirrorFallback": payload::flag_or(row, "mirrorFallback", true),
        "groupId": optional_integer(row, "groupId"),
    })
}

/// One `subscription_group` row; its switch defaults to on.
pub fn group_from_row(row: &Value) -> Value {
    json!({
        "id": payload::integer_or(row, "id", 0),
        "name": payload::text_or_empty(row, "name"),
        "autoUpdateEnabled": payload::flag_or(row, "autoUpdateEnabled", true),
        "addedAt": payload::integer_or(row, "addedAt", 0),
    })
}

/// One `subscription_auto_update_item` row; `changed` is exactly `1` (not any truthy number).
pub fn item_from_row(row: &Value) -> Value {
    json!({
        "batchId": payload::text_or_empty(row, "batchId"),
        "subscriptionId": payload::integer_or(row, "subscriptionId", 0),
        "status": auto_update_status(row.get("status").and_then(Value::as_str)),
        "changed": payload::integer(row, "changed") == Some(1),
        "ruleCount": payload::integer_or(row, "ruleCount", 0),
    })
}

/// The default name for a picked local rule file: the last `/` segment without its `.txt`.
/// `None` means the caller falls back to the localised "local rule file" label.
pub fn local_name_of(uri: &str) -> Option<String> {
    let segment = uri.rsplit('/').next().unwrap_or_default();
    let trimmed = if segment.to_lowercase().ends_with(".txt") {
        &segment[..segment.len() - 4]
    } else {
        segment
    };
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_owned())
    }
}

fn is_local(source: &str) -> bool {
    source == "local"
}

/// Validates one add form and returns the row (`record`) the repository inserts.
///
/// Errors are tokens (`pickFile`, `pickTxt`, URL kinds, mirror kinds); the l10n sentence is built
/// in Dart. A `null` record name means "use the localised local-file label".
pub fn prepare_add(request: &Value) -> Value {
    let raw_url = payload::text_or_empty(request, "url");
    let source = source_type(request.get("sourceType").and_then(Value::as_str));
    let provided_name = payload::text_or_empty(request, "name").trim().to_owned();
    let trimmed_url = raw_url.trim().to_owned();
    let mirror_fallback = payload::flag_or(request, "mirrorFallback", true);

    if is_local(source) {
        if trimmed_url.is_empty() {
            return json!({ "error": "pickFile" });
        }
        let picked = trimmed_url.rsplit('/').next().unwrap_or_default();
        if !picked.to_lowercase().ends_with(".txt") {
            return json!({ "error": "pickTxt" });
        }
        let name = if provided_name.is_empty() {
            local_name_of(&trimmed_url)
        } else {
            Some(provided_name)
        };
        return json!({
            "record": {
                "id": 0,
                "url": trimmed_url,
                "name": name,
                "sourceType": source,
                "kind": kind(request.get("kind").and_then(Value::as_str)),
                "enabled": true,
                "ruleCount": 0,
                "lastUpdated": 0,
                "addedAt": payload::integer_or(request, "nowMs", 0),
                "importState": "importing",
                "importError": null,
                "httpEtag": null,
                "httpLastModified": null,
                "ruleSetHash": null,
                "lastAttemptAt": 0,
                "consecutiveFailureCount": 0,
                "mirrorTemplate": null,
                "mirrorFallback": mirror_fallback,
                "groupId": optional_integer(request, "groupId"),
            },
        });
    }

    let parts = UrlParts::from(request);
    if let Err(error) = url::validate(&trimmed_url, &parts) {
        return json!({ "error": error.as_str() });
    }
    let normalized_mirror =
        match url::normalize_template(request.get("mirrorTemplate").and_then(Value::as_str)) {
            Ok(template) => template,
            Err(error) => return json!({ "error": error.as_str() }),
        };
    let name = if provided_name.is_empty() {
        url::extract_name(&trimmed_url, &parts.path, &parts.host)
    } else {
        provided_name
    };
    json!({
        "record": {
            "id": 0,
            "url": trimmed_url,
            "name": name,
            "sourceType": source,
            "kind": kind(request.get("kind").and_then(Value::as_str)),
            "enabled": true,
            "ruleCount": 0,
            "lastUpdated": 0,
            "addedAt": payload::integer_or(request, "nowMs", 0),
            "importState": "importing",
            "importError": null,
            "httpEtag": null,
            "httpLastModified": null,
            "ruleSetHash": null,
            "lastAttemptAt": 0,
            "consecutiveFailureCount": 0,
            "mirrorTemplate": normalized_mirror,
            "mirrorFallback": mirror_fallback,
            "groupId": optional_integer(request, "groupId"),
        },
        "needsReimport": true,
    })
}

/// Validates one edit form against the stored row and returns the column values to write plus
/// whether the stored rules belong to an address/kind that just changed.
pub fn prepare_edit(request: &Value) -> Value {
    let existing_map = payload::child(request, "existing");
    let existing = Value::Object(existing_map.clone());
    let existing_url = payload::text_or_empty(&existing, "url");
    let existing_name = payload::text_or_empty(&existing, "name");
    let existing_kind = payload::text_or_empty(&existing, "kind");
    let source = source_type(existing.get("sourceType").and_then(Value::as_str));
    let local = is_local(source);

    let new_url = payload::text_or_empty(request, "url");
    let trimmed_url = if local {
        existing_url.clone()
    } else {
        new_url.trim().to_owned()
    };
    let parts = UrlParts::from(request);
    if !local {
        if let Err(error) = url::validate(&trimmed_url, &parts) {
            return json!({ "error": error.as_str() });
        }
    }
    let normalized_mirror = if local {
        None
    } else {
        match url::normalize_template(request.get("mirrorTemplate").and_then(Value::as_str)) {
            Ok(template) => template,
            Err(error) => return json!({ "error": error.as_str() }),
        }
    };
    let provided_name = payload::text_or_empty(request, "name").trim().to_owned();
    let name = if provided_name.is_empty() {
        if local {
            existing_name
        } else {
            url::extract_name(&trimmed_url, &parts.path, &parts.host)
        }
    } else {
        provided_name
    };
    let normalized_kind = kind(request.get("kind").and_then(Value::as_str));
    let source_changed = trimmed_url != existing_url || normalized_kind != existing_kind;
    json!({
        "values": {
            "name": name,
            "url": trimmed_url,
            "kind": normalized_kind,
            "groupId": optional_integer(request, "groupId"),
            "mirrorTemplate": normalized_mirror,
            "mirrorFallback": payload::flag_or(request, "mirrorFallback", true),
            "resetValidators": source_changed,
        },
        "needsReimport": source_changed,
    })
}

/// Trimmed mirror-template form values; an empty name or template is rejected before the
/// repository's name-clash check.
pub fn prepare_mirror(request: &Value) -> Value {
    let name = payload::text_or_empty(request, "name").trim().to_owned();
    let template = payload::text_or_empty(request, "template")
        .trim()
        .to_owned();
    if name.is_empty() || template.is_empty() {
        return json!({ "error": "empty" });
    }
    json!({ "name": name, "template": template })
}

/// Maps a list of rows of one table.
pub fn rows(request: &Value, table: &str) -> Value {
    let parse: fn(&Value) -> Value = match table {
        "groups" => group_from_row,
        "items" => item_from_row,
        _ => record_from_row,
    };
    Value::Array(
        payload::list(request, "rows")
            .iter()
            .map(parse)
            .collect::<Vec<Value>>(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn storage_normalisation() {
        assert_eq!(source_type(Some("local")), "local");
        assert_eq!(source_type(Some("LOCAL")), "remote");
        assert_eq!(kind(Some(" HOSTS ")), "hosts");
        assert_eq!(kind(Some("weird")), "domain");
        assert_eq!(import_state(Some("failed")), "failed");
        assert_eq!(auto_update_status(Some("x")), "pending_retry");
    }

    #[test]
    fn record_defaults() {
        let row = record_from_row(&json!({}));
        assert_eq!(row["enabled"], json!(true));
        assert_eq!(row["mirrorFallback"], json!(true));
        assert_eq!(row["sourceType"], json!("remote"));
        assert_eq!(row["kind"], json!("domain"));
        assert_eq!(row["importState"], json!("ready"));
        assert_eq!(row["groupId"], Value::Null);
    }

    #[test]
    fn local_names() {
        assert_eq!(
            local_name_of("content://x/y/Rules.TXT"),
            Some("Rules".into())
        );
        assert_eq!(local_name_of("content://x/y/.txt"), None);
        assert_eq!(local_name_of(""), None);
    }
}
