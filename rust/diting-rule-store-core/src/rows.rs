use std::collections::BTreeMap;

use serde_json::{json, Value};

use crate::probe::{flag, get, text};

fn subscription_id_of(source: &str) -> Option<i64> {
    source
        .strip_prefix("sub_")
        .or_else(|| source.strip_prefix("staging_sub_"))
        .and_then(|id| id.parse::<i64>().ok())
}

fn origin_of(sources: &[(String, bool)]) -> &'static str {
    if sources.iter().any(|(source, _)| source == "preset") {
        return "preset";
    }
    if sources
        .iter()
        .any(|(source, _)| subscription_id_of(source).is_some())
    {
        return "subscription";
    }
    "user"
}

fn subscription_name_of(
    sources: &[(String, bool)],
    subscriptions: &BTreeMap<i64, String>,
) -> Option<String> {
    for (source, _) in sources {
        let Some(id) = subscription_id_of(source) else {
            continue;
        };
        if let Some(name) = subscriptions.get(&id) {
            return Some(name.clone());
        }
    }
    None
}

pub fn subscriptions(value: &Value) -> BTreeMap<i64, String> {
    let mut names = BTreeMap::new();
    for row in crate::probe::list(value, "subscriptions") {
        let (Some(id), Some(name)) = (crate::probe::integer(row, "id"), text(row, "name")) else {
            continue;
        };
        names.insert(id, name);
    }
    names
}

pub fn rule_from_split(
    kind: &str,
    row: &Value,
    sources: &[(String, bool)],
    subscriptions: &BTreeMap<i64, String>,
) -> Value {
    let source_enabled = sources.is_empty() || sources.iter().any(|(_, enabled)| *enabled);
    let app_scope = text(row, "appScope").map(|scope| scope.trim().to_string());
    let app_scope = match app_scope {
        Some(scope) if !scope.is_empty() => Value::String(scope),
        _ => Value::Null,
    };
    let rewrite = kind == "rewrite";
    json!({
        "id": match get(row, "id") {
            Some(Value::String(id)) => Value::String(id.clone()),
            Some(Value::Number(number)) => Value::String(number.to_string()),
            _ => Value::String(String::new()),
        },
        "pattern": text(row, "pattern").unwrap_or_default(),
        "enabled": flag(row, "enabled").unwrap_or(false) && source_enabled,
        "important": !rewrite && flag(row, "important").unwrap_or(false),
        "group": text(row, "groupName"),
        "subscriptionName": subscription_name_of(sources, subscriptions),
        "target": if rewrite { text(row, "targetValue") } else { None },
        "appScope": app_scope,
        "appInverted": !rewrite && flag(row, "appInverted").unwrap_or(false),
        "source": origin_of(sources),
    })
}

pub fn rule_from_joined(
    kind: &str,
    joined: &[Value],
    subscriptions: &BTreeMap<i64, String>,
) -> Vec<Value> {
    let mut rules = Vec::new();
    let mut index = 0;
    while index < joined.len() {
        let row = &joined[index];
        let id = get(row, "id").and_then(Value::as_i64);
        let mut sources = Vec::new();
        while index < joined.len() && get(&joined[index], "id").and_then(Value::as_i64) == id {
            if let Some(source) = text(&joined[index], "sourceName") {
                sources.push((source, flag(&joined[index], "sourceEnabled") == Some(true)));
            }
            index += 1;
        }
        rules.push(rule_from_split(kind, row, &sources, subscriptions));
    }
    rules
}

pub fn rule_from_sources(
    kind: &str,
    rules: &[Value],
    sources: &[Value],
    subscriptions: &BTreeMap<i64, String>,
) -> Vec<Value> {
    let mut by_rule: BTreeMap<i64, Vec<(String, bool)>> = BTreeMap::new();
    for row in sources {
        let (Some(rule_id), Some(source)) =
            (crate::probe::integer(row, "ruleId"), text(row, "source"))
        else {
            continue;
        };
        by_rule
            .entry(rule_id)
            .or_default()
            .push((source, flag(row, "enabled") == Some(true)));
    }
    rules
        .iter()
        .map(|row| {
            let rule_id = crate::probe::integer(row, "id").unwrap_or_default();
            let sources = by_rule.get(&rule_id).cloned().unwrap_or_default();
            rule_from_split(kind, row, &sources, subscriptions)
        })
        .collect()
}

#[cfg(test)]
#[path = "rows/tests.rs"]
mod tests;
