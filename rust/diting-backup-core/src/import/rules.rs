//! Database-backed groups: subscriptions and the three rule tables.
//!
//! The plan carries the statements; the app still runs them (`sqflite` owns the connection), but
//! every dedupe key and counter is decided here. Rows inserted earlier in the same file are added
//! to the seen set, exactly like the app's "insert then query" loop.

use serde_json::{json, Value};

use super::{as_record, text_field, Outcome, Plan};
use crate::groups::Group;
use crate::value::{array, get, integer, text, truthy};

fn subscription_kind(value: &Value) -> &'static str {
    match get(value, "kind").and_then(Value::as_str) {
        Some(kind) if kind.trim().to_lowercase() == "hosts" => "hosts",
        _ => "domain",
    }
}

fn subscription_source(value: &Value) -> &'static str {
    match get(value, "sourceType").and_then(Value::as_str) {
        Some("local") => "local",
        _ => "remote",
    }
}

fn is_false(value: &Value) -> bool {
    truthy(value, "enabled") == Some(false)
}

fn pair_list(items: &[Value], left: &str, right: &str) -> Vec<(String, String)> {
    items
        .iter()
        .filter_map(|row| Some((text(row, left)?, text(row, right).unwrap_or_default())))
        .collect()
}

pub fn subscriptions(
    value: &Value,
    current: &Value,
    now: i64,
    has_database: bool,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    if !value.is_object() {
        return Err("subsNotObject");
    }
    if !has_database {
        return Err("noDbSubs");
    }
    let mut outcome = Outcome::new(Group::Subscriptions);

    let mut group_names: Vec<String> = array(current, "groupNames")
        .iter()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect();
    if let Some(Value::Array(groups)) = get(value, "groups") {
        for item in groups {
            if as_record(item).is_none() {
                continue;
            }
            let Some(name) = text(item, "name") else {
                continue;
            };
            if name.trim().is_empty() {
                continue;
            }
            // An existing group keeps its local switch; only a new one is created.
            if group_names.contains(&name) {
                outcome.skipped += 1;
                continue;
            }
            let auto_update = get(item, "autoUpdateEnabled") != Some(&Value::Bool(false));
            plan.op(json!({
                "op": "subsGroup",
                "name": name,
                "autoUpdateEnabled": auto_update,
            }));
            group_names.push(name);
            outcome.added += 1;
        }
    }

    // Mirror templates have no incremental write path; the insert ignores duplicates.
    if let Some(Value::Array(templates)) = get(value, "mirrorTemplates") {
        for item in templates {
            let (Some(name), Some(template)) =
                (text_field(item, "name"), text_field(item, "template"))
            else {
                continue;
            };
            plan.op(json!({
                "op": "subsMirror",
                "name": name,
                "template": template,
                "addedAt": now,
            }));
        }
    }

    let mut url_kinds = pair_list(&array(current, "urls"), "url", "kind");
    if let Some(Value::Array(items)) = get(value, "items") {
        for item in items {
            if as_record(item).is_none() {
                outcome.skipped += 1;
                continue;
            }
            let Some(url) = text(item, "url") else {
                outcome.skipped += 1;
                continue;
            };
            if url.trim().is_empty() {
                outcome.skipped += 1;
                continue;
            }
            let kind = subscription_kind(item);
            if url_kinds.contains(&(url.clone(), String::from(kind))) {
                outcome.skipped += 1;
                continue;
            }
            plan.op(json!({
                "op": "subsItem",
                "url": url,
                "name": text(item, "name").unwrap_or_else(|| url.clone()),
                "kind": kind,
                "sourceType": subscription_source(item),
                "enabled": !is_false(item),
                "mirrorTemplate": text(item, "mirrorTemplate"),
                "mirrorFallback": truthy(item, "mirrorFallback") != Some(false),
                "groupName": text(item, "groupName"),
                // Importing the address, not its contents: zero count and untouched timestamps so
                // the first refresh downloads.
                "ruleCount": 0,
                "lastUpdated": 0,
                "addedAt": now,
            }));
            url_kinds.push((url, String::from(kind)));
            outcome.added += 1;
        }
    }

    Ok(outcome)
}

/// Dedupe key matching the unique indexes on the block/allow rule tables.
fn rule_key(pattern: &str, important: bool, app_scope: Option<&str>) -> String {
    format!(
        "{}\u{0}{}\u{0}{}",
        pattern,
        u8::from(important),
        app_scope.unwrap_or_default()
    )
}

pub fn domain_rules(
    value: &Value,
    current: &Value,
    now: i64,
    has_database: bool,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    let Value::Array(items) = value else {
        return Err("rulesNotArray");
    };
    if !has_database {
        return Err("noDbRules");
    }
    let mut seen: Vec<(bool, String)> = Vec::new();
    for (key, allow) in [("block", false), ("allow", true)] {
        for row in array(current, key) {
            let pattern = text(&row, "pattern").unwrap_or_default();
            let important = truthy(&row, "important").unwrap_or(false);
            let scope = text_field(&row, "appScope");
            seen.push((allow, rule_key(&pattern, important, scope.as_deref())));
        }
    }

    let mut outcome = Outcome::new(Group::DomainRules);
    for item in items {
        if as_record(item).is_none() {
            outcome.skipped += 1;
            continue;
        }
        let Some(pattern) = text_field(item, "pattern") else {
            outcome.skipped += 1;
            continue;
        };
        let allow = get(item, "kind").and_then(Value::as_str) == Some("allow");
        let important = truthy(item, "important").unwrap_or(false);
        let app_scope = text_field(item, "appScope");
        let key = rule_key(&pattern, important, app_scope.as_deref());
        // Dedupe without overwriting: a per-app rule must not degrade into a global block.
        if seen.contains(&(allow, key.clone())) {
            outcome.skipped += 1;
            continue;
        }
        seen.push((allow, key));
        let raw_line = text_field(item, "rawLine").unwrap_or_else(|| pattern.clone());
        plan.op(json!({
            "op": "ruleInsert",
            "table": if allow { "allow_rule" } else { "block_rule" },
            "row": {
                "pattern": pattern,
                "rawLine": raw_line,
                "addedAt": now,
                "enabled": if is_false(item) { 0 } else { 1 },
                "groupName": text_field(item, "group"),
                "important": i32::from(important),
                "appScope": app_scope,
                "appInverted": i32::from(truthy(item, "appInverted").unwrap_or(false)),
                // Keep the stored flags in step with the pattern, as the repository does.
                "isWildcard": i32::from(pattern.contains('*')),
                "denyallow": Value::Null,
                "isRegex": 0,
                "dnsType": Value::Null,
            },
        }));
        outcome.added += 1;
    }
    Ok(outcome)
}

pub fn rewrite(
    group: Group,
    value: &Value,
    current: &Value,
    now: i64,
    has_database: bool,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    let Value::Array(items) = value else {
        return Err("rewriteNotArray");
    };
    if !has_database {
        return Err("noDbRewrite");
    }
    let target_types = group.target_types();
    let mut rows = array(current, "rows");
    let mut outcome = Outcome::new(group);

    for item in items {
        if as_record(item).is_none() {
            outcome.skipped += 1;
            continue;
        }
        let (Some(pattern), Some(target_type), Some(target_value)) = (
            text_field(item, "pattern"),
            text(item, "targetType"),
            text(item, "targetValue"),
        ) else {
            outcome.skipped += 1;
            continue;
        };
        if !target_types.contains(&target_type.as_str()) {
            outcome.skipped += 1;
            continue;
        }
        let raw_line =
            text_field(item, "rawLine").unwrap_or_else(|| format!("{pattern} {target_value}"));
        let existing = rows.iter().position(|row| {
            text(row, "pattern").as_deref() == Some(pattern.as_str())
                && text(row, "targetType").as_deref() == Some(target_type.as_str())
        });
        match existing {
            None => {
                plan.op(json!({
                    "op": "rewriteInsert",
                    "row": {
                        "pattern": pattern,
                        "targetType": target_type,
                        "targetValue": target_value,
                        "rawLine": raw_line,
                        "addedAt": now,
                        "enabled": if is_false(item) { 0 } else { 1 },
                    },
                }));
                rows.push(json!({
                    "id": 0,
                    "pattern": pattern,
                    "targetType": target_type,
                    "targetValue": target_value,
                }));
                outcome.added += 1;
            }
            Some(index) => {
                // Same pattern and type with a new value is an edit, not a second rule.
                if text(&rows[index], "targetValue").as_deref() == Some(target_value.as_str()) {
                    outcome.skipped += 1;
                    continue;
                }
                plan.op(json!({
                    "op": "rewriteUpdate",
                    "id": integer(&rows[index], "id").unwrap_or_default(),
                    "targetValue": target_value,
                    "rawLine": raw_line,
                }));
                rows[index]["targetValue"] = Value::String(target_value);
                outcome.updated += 1;
            }
        }
    }
    Ok(outcome)
}

pub fn address_rules(
    value: &Value,
    current: &Value,
    now: i64,
    has_database: bool,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    let Value::Array(items) = value else {
        return Err("addressNotArray");
    };
    if !has_database {
        return Err("noDbAddress");
    }
    let mut seen = pair_list(&array(current, "rows"), "pattern", "kind");
    let mut outcome = Outcome::new(Group::AddressRules);
    for item in items {
        if as_record(item).is_none() {
            outcome.skipped += 1;
            continue;
        }
        let (Some(pattern), Some(kind)) = (text_field(item, "pattern"), text(item, "kind")) else {
            outcome.skipped += 1;
            continue;
        };
        if kind.is_empty() {
            outcome.skipped += 1;
            continue;
        }
        if seen.contains(&(pattern.clone(), kind.clone())) {
            outcome.skipped += 1;
            continue;
        }
        let raw_line = text_field(item, "rawLine").unwrap_or_else(|| pattern.clone());
        plan.op(json!({
            "op": "addressInsert",
            "row": {
                "pattern": pattern,
                "kind": kind,
                "rawLine": raw_line,
                "addedAt": now,
                "enabled": if is_false(item) { 0 } else { 1 },
            },
        }));
        seen.push((pattern, kind));
        outcome.added += 1;
    }
    Ok(outcome)
}
