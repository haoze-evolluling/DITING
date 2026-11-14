//! JSON decoding for the C ABI. Requests are JSON objects; a shape that does not fit is `None`, so a
//! drifted caller fails loudly instead of silently resolving against an empty profile list.

use serde_json::Value;

use crate::profile::{NetworkContext, NetworkMatch, Profile};

fn text(value: &Value, field: &str) -> String {
    value
        .get(field)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn flag(value: &Value, field: &str) -> bool {
    value.get(field).and_then(Value::as_bool).unwrap_or(false)
}

fn optional_flag(value: &Value, field: &str) -> Option<bool> {
    value.get(field).and_then(Value::as_bool)
}

fn optional_text(value: &Value, field: &str) -> Option<String> {
    value
        .get(field)
        .and_then(Value::as_str)
        .map(str::to_string)
        .filter(|text| !text.is_empty())
}

fn text_list(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

/// Decodes the network context object.
pub fn decode_context(request: &Value) -> NetworkContext {
    let context = request.get("networkCtx").cloned().unwrap_or(Value::Null);
    NetworkContext {
        kind: text(&context, "type"),
        metered: flag(&context, "metered"),
        roaming: flag(&context, "roaming"),
        validated: flag(&context, "validated"),
        ssid: text(&context, "ssid"),
        bssid: text(&context, "bssid"),
    }
}

fn decode_match(profile: &Value) -> NetworkMatch {
    let guard = profile.get("networkMatch").cloned().unwrap_or(Value::Null);
    NetworkMatch {
        types: text_list(guard.get("types")),
        metered: optional_flag(&guard, "metered"),
        roaming: optional_flag(&guard, "roaming"),
        validated: optional_flag(&guard, "validated"),
        ssid: optional_text(&guard, "ssid"),
        bssid: optional_text(&guard, "bssid"),
    }
}

/// Decodes the profile list; a profile without an `id` is dropped (an unnamed reference is useless).
pub fn decode_profiles(request: &Value) -> Vec<Profile> {
    let Some(items) = request.get("profiles").and_then(Value::as_array) else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| {
            let id = text(item, "id");
            if id.is_empty() {
                return None;
            }
            Some(Profile {
                id: id.clone(),
                name: {
                    let name = text(item, "name");
                    if name.is_empty() {
                        id
                    } else {
                        name
                    }
                },
                priority: item.get("priority").and_then(Value::as_i64).unwrap_or(100),
                enabled: item.get("enabled").and_then(Value::as_bool).unwrap_or(true),
                network_match: decode_match(item),
                upstream_set: text(item, "upstreamSet"),
                rule_group_states: text_list(item.get("ruleGroupStates")),
                feature_toggles: item
                    .get("featureToggles")
                    .cloned()
                    .filter(Value::is_object)
                    .unwrap_or_else(|| Value::Object(Default::default())),
            })
        })
        .collect()
}

/// The optional fallback profile id.
pub fn fallback_id(request: &Value) -> String {
    text(request, "fallbackId")
}
