//! Prefs-backed groups: providers, bootstrap, cache, outbound.
//!
//! Merging is content-based: ids and timestamps are generated locally, so comparing them would
//! report an update on every re-import of the same file.

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use super::{same_order, string_set, Outcome, Plan};
use crate::groups::Group;
use crate::value::{array, config_signature, get, integer, slug_of, text, trimmed};

pub fn providers(value: &Value, current: &Value, plan: &mut Plan) -> Outcome {
    // Both the legacy array and the newer `{items, selection}` form are accepted.
    let incoming: Vec<Value> = match value {
        Value::Array(items) => items.clone(),
        Value::Object(record) => match record.get("items") {
            Some(Value::Array(items)) => items.clone(),
            _ => return Outcome::failed(Group::Providers, "providersNotArray"),
        },
        _ => return Outcome::failed(Group::Providers, "providersNotArray"),
    };

    let mut existing = decode_providers(get(current, "itemsJson"));
    let mut by_name: BTreeMap<String, usize> = BTreeMap::new();
    for (index, item) in existing.iter().enumerate() {
        by_name.insert(name_of(item), index);
    }

    let mut outcome = Outcome::new(Group::Providers);
    for item in &incoming {
        let Some(record) = item.as_object() else {
            outcome.skipped += 1;
            continue;
        };
        let name = name_of(item);
        if name.is_empty() {
            outcome.skipped += 1;
            continue;
        }
        let normalized = with_id(record, &name);
        match by_name.get(&name) {
            None => {
                existing.push(Value::Object(normalized));
                by_name.insert(name, existing.len() - 1);
                outcome.added += 1;
            }
            Some(&index) => {
                if config_signature(&existing[index])
                    == config_signature(&Value::Object(normalized.clone()))
                {
                    outcome.skipped += 1;
                } else {
                    // Keep the local id: UI selections and candidate lists reference it.
                    existing[index] = Value::Object(keep_id(normalized, &existing[index]));
                    outcome.updated += 1;
                }
            }
        }
    }

    if outcome.added > 0 || outcome.updated > 0 {
        plan.write(
            "providers.items",
            Value::String(encode(&Value::Array(existing.clone()))),
        );
    }
    if let Some(selection) = get(value, "selection") {
        apply_selection(selection, current, &existing, plan);
    }
    outcome
}

fn name_of(provider: &Value) -> String {
    text(provider, "name")
        .unwrap_or_default()
        .trim()
        .to_string()
}

/// Fill in a missing id from the name so re-imports stay idempotent.
fn with_id(provider: &Map<String, Value>, name: &str) -> Map<String, Value> {
    let mut record = provider.clone();
    let present = matches!(record.get("id"), Some(Value::String(id)) if !id.trim().is_empty());
    if !present {
        record.insert(
            String::from("id"),
            Value::String(format!("user_{}", slug_of(name))),
        );
    }
    record
}

fn keep_id(incoming: Map<String, Value>, current: &Value) -> Map<String, Value> {
    let mut record = incoming;
    if let Some(Value::String(id)) = get(current, "id") {
        if !id.is_empty() {
            record.insert(String::from("id"), Value::String(id.clone()));
        }
    }
    record
}

fn decode_providers(raw: Option<&Value>) -> Vec<Value> {
    let Some(Value::String(text)) = raw else {
        return Vec::new();
    };
    if text.trim().is_empty() {
        return Vec::new();
    }
    match serde_json::from_str::<Value>(text) {
        Ok(Value::Array(items)) => items,
        // Corrupt or non-array local JSON means "no providers yet"; the import then adds them.
        _ => Vec::new(),
    }
}

fn encode(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| String::from("[]"))
}

/// `(name, PROTOCOL)` and id lookups over presets plus the merged custom providers.
fn provider_index(current: &Value, merged: &[Value]) -> BTreeMap<String, String> {
    let mut index = BTreeMap::new();
    for preset in array(current, "presets") {
        add_to_index(&mut index, &preset);
    }
    for provider in merged {
        add_to_index(&mut index, provider);
    }
    index
}

fn add_to_index(index: &mut BTreeMap<String, String>, provider: &Value) {
    let Some(id) = text(provider, "id") else {
        return;
    };
    index.insert(id.clone(), id.clone());
    if let Some(name) = text(provider, "name") {
        let protocol = text(provider, "protocol")
            .unwrap_or_default()
            .to_uppercase();
        index.insert(format!("{name}\u{0}{protocol}"), id);
    }
}

/// Local id for a reference, else the `(name, protocol)` fallback of backups written on a device
/// whose ids no longer exist.
fn resolve(reference: &Value, index: &BTreeMap<String, String>) -> Option<String> {
    let id = text(reference, "id");
    if let Some(id) = &id {
        if !id.is_empty() && index.contains_key(id) {
            return Some(id.clone());
        }
    }
    if let Some(name) = text(reference, "name") {
        if !name.is_empty() {
            let protocol = match get(reference, "protocol") {
                Some(Value::String(text)) => text.to_uppercase(),
                _ => String::new(),
            };
            // A name that no longer exists resolves to nothing rather than to a broken id.
            return index.get(&format!("{name}\u{0}{protocol}")).cloned();
        }
    }
    id.filter(|id| !id.is_empty())
}

fn ids_of(references: Option<&Value>, index: &BTreeMap<String, String>) -> Vec<String> {
    let mut ids: Vec<String> = Vec::new();
    let Some(Value::Array(items)) = references else {
        return ids;
    };
    for item in items {
        if !item.is_object() {
            continue;
        }
        if let Some(id) = resolve(item, index) {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
    }
    ids
}

fn apply_selection(value: &Value, current: &Value, merged: &[Value], plan: &mut Plan) {
    if !value.is_object() {
        return;
    }
    let index = provider_index(current, merged);

    if let Some(selected) = get(value, "selectedProvider") {
        if selected.is_object() {
            if let Some(id) = resolve(selected, &index) {
                plan.write("providers.selectedId", Value::String(id));
            }
        }
    }
    if let Some(mode) = text(value, "resolutionMode") {
        if !mode.is_empty() {
            plan.write("providers.resolutionMode", Value::String(mode));
        }
    }
    if let Some(domain) = trimmed(value, "raceTestDomain") {
        plan.write("providers.raceTestDomain", Value::String(domain));
    }

    // An empty list is meaningful: the user may have cleared the candidates.
    for (key, field) in [
        ("raceProviderRefs", "providers.race"),
        ("smartPredictionProviderRefs", "providers.smartPrediction"),
        ("parallelRaceProviderRefs", "providers.parallelRace"),
        ("primaryBackupProviderRefs", "providers.primaryBackup"),
        ("latencyTestProviderRefs", "providers.latencyTest"),
    ] {
        if let Some(references) = get(value, key) {
            if references.is_array() {
                plan.write(field, json!(ids_of(Some(references), &index)));
            }
        }
    }

    if let Some(visibility) = get(value, "homeProviderVisibility") {
        if visibility.is_object() {
            let mut protocols = string_set(
                &get(visibility, "visibleProtocols")
                    .cloned()
                    .unwrap_or(Value::Null),
            );
            if protocols.is_empty() {
                // An empty list means "no protocol filter", not "hide everything".
                protocols = string_set(
                    &get(current, "homeVisibleProtocols")
                        .cloned()
                        .unwrap_or(Value::Null),
                );
            }
            plan.write(
                "providers.homeVisibility",
                json!({
                    "visibleProtocols": protocols,
                    "hiddenProviderIds":
                        ids_of(get(visibility, "hiddenProviderRefs"), &index),
                    "visibleProviderIds":
                        ids_of(get(visibility, "visibleProviderRefs"), &index),
                }),
            );
        }
    }
}

pub fn bootstrap(value: &Value, current: &Value, plan: &mut Plan) -> Outcome {
    if !value.is_object() {
        return Outcome::failed(Group::Bootstrap, "bootstrapNotObject");
    }
    let mut outcome = Outcome::new(Group::Bootstrap);

    match get(value, "enabled").and_then(Value::as_bool) {
        Some(enabled) => {
            if get(current, "enabled").and_then(Value::as_bool) == Some(enabled) {
                outcome.skipped += 1;
            } else {
                plan.write("bootstrap.enabled", json!(enabled));
                outcome.added += 1;
            }
        }
        None => outcome.skipped += 1,
    }

    match get(value, "presetIds") {
        Some(Value::Array(_)) => {
            let incoming = string_set(get(value, "presetIds").unwrap_or(&Value::Null));
            let local = string_set(get(current, "presetIds").unwrap_or(&Value::Null));
            if same_order(&incoming, &local) {
                outcome.skipped += 1;
            } else {
                plan.write("bootstrap.presetIds", json!(incoming));
                outcome.added += 1;
            }
        }
        _ => outcome.skipped += 1,
    }

    match get(value, "custom") {
        Some(custom) if !custom.is_null() => {
            // The field is the raw custom node text, so the encoded JSON is what gets stored.
            let encoded = encode(custom);
            if get(current, "customJson").and_then(Value::as_str) == Some(encoded.as_str()) {
                outcome.skipped += 1;
            } else {
                plan.write("bootstrap.customJson", Value::String(encoded));
                outcome.added += 1;
            }
        }
        _ => outcome.skipped += 1,
    }

    outcome
}

/// Written as one policy so the engine never sees a new mode with an old TTL.
pub fn cache(value: &Value, current: &Value, plan: &mut Plan) -> Outcome {
    if !value.is_object() {
        return Outcome::failed(Group::Cache, "cacheNotObject");
    }
    // Missing keys fall back to local values so all nine stay consistent.
    let pick_text =
        |key: &str, fallback: &str| text(value, key).unwrap_or_else(|| fallback.to_string());
    let local_text = |key: &str| text(current, key).unwrap_or_default();
    let pick_bool =
        |key: &str, fallback: bool| get(value, key).and_then(Value::as_bool).unwrap_or(fallback);
    let pick_int = |key: &str, fallback: i64| integer(value, key).unwrap_or(fallback);

    let next = json!({
        "preset": pick_text("preset", &local_text("preset")),
        "enabled": pick_bool("enabled", get(current, "enabled").and_then(Value::as_bool).unwrap_or(false)),
        "mode": pick_text("mode", &local_text("mode")),
        "maxTtlSeconds": pick_int("maxTtlSeconds", integer(current, "maxTtlSeconds").unwrap_or(0)),
        "fixedTtlSeconds": pick_int("fixedTtlSeconds", integer(current, "fixedTtlSeconds").unwrap_or(0)),
        "minTtlEnabled": pick_bool("minTtlEnabled", get(current, "minTtlEnabled").and_then(Value::as_bool).unwrap_or(false)),
        "minTtlSeconds": pick_int("minTtlSeconds", integer(current, "minTtlSeconds").unwrap_or(0)),
        "staleFallbackEnabled": pick_bool("staleFallbackEnabled", get(current, "staleFallbackEnabled").and_then(Value::as_bool).unwrap_or(false)),
        "staleFallbackSeconds": pick_int("staleFallbackSeconds", integer(current, "staleFallbackSeconds").unwrap_or(0)),
    });

    let mut unchanged = true;
    for key in [
        "preset",
        "enabled",
        "mode",
        "maxTtlSeconds",
        "fixedTtlSeconds",
        "minTtlEnabled",
        "minTtlSeconds",
        "staleFallbackEnabled",
        "staleFallbackSeconds",
    ] {
        let local = match key {
            "preset" | "mode" => Value::String(local_text(key)),
            "enabled" | "minTtlEnabled" | "staleFallbackEnabled" => {
                Value::from(get(current, key).and_then(Value::as_bool).unwrap_or(false))
            }
            _ => Value::from(integer(current, key).unwrap_or(0)),
        };
        if next.get(key) != Some(&local) {
            unchanged = false;
        }
    }
    if unchanged {
        return Outcome {
            skipped: 1,
            ..Outcome::new(Group::Cache)
        };
    }
    plan.write("cache.config", next);
    Outcome {
        // The nine keys are one policy; reporting 9 would look like nine rules.
        added: 1,
        ..Outcome::new(Group::Cache)
    }
}

/// Non-secret fields only, and never auto-enabled: an on-switch without local credentials would
/// fail to connect.
pub fn outbound(value: &Value, current: &Value, plan: &mut Plan) -> Outcome {
    if !value.is_object() {
        return Outcome::failed(Group::Outbound, "outboundNotObject");
    }
    let mut outcome = Outcome::new(Group::Outbound);
    for (key, field) in [
        ("protocol", "outbound.protocol"),
        ("host", "outbound.host"),
        // An early 2.0 build wrote `outbound_proxy_app_package`, which always read empty.
        ("proxyAppPackage", "outbound.app"),
    ] {
        let Some(raw) = text(value, key) else {
            continue;
        };
        if raw.is_empty() {
            continue;
        }
        if get(current, key).and_then(Value::as_str) == Some(raw.as_str()) {
            outcome.skipped += 1;
            continue;
        }
        plan.write(field, Value::String(raw));
        outcome.added += 1;
    }
    if let Some(port) = integer(value, "port") {
        if integer(current, "port") == Some(port) {
            outcome.skipped += 1;
        } else {
            plan.write("outbound.port", json!(port));
            outcome.added += 1;
        }
    }
    outcome
}
