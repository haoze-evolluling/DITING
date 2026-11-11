//! App-list groups: excluded / blocked / allowlist / HTTPS inspection.
//!
//! All four merge with local data and an import never removes an entry.

use serde_json::{json, Value};

use super::{string_set, union, Outcome, Plan};
use crate::groups::Group;
use crate::value::{as_object, boolean, get};

pub fn excluded(value: &Value, current: &Value, plan: &mut Plan) -> Outcome {
    let incoming = string_set(value);
    if incoming.is_empty() {
        return Outcome {
            skipped: 1,
            ..Outcome::new(Group::Excluded)
        };
    }
    let local = string_set(&get(current, "packages").cloned().unwrap_or(Value::Null));
    let merged = union(&local, &incoming);
    let added = merged.len() - local.len();
    plan.write("excluded.packages", json!(merged));
    Outcome {
        added: added as u64,
        skipped: (incoming.len() - added) as u64,
        ..Outcome::new(Group::Excluded)
    }
}

pub fn blocked(value: &Value, current: &Value, plan: &mut Plan) -> Result<Outcome, &'static str> {
    if !value.is_object() {
        return Err("blockedNotObject");
    }
    let incoming = string_set(&get(value, "packages").cloned().unwrap_or(Value::Null));
    let local = string_set(&get(current, "packages").cloned().unwrap_or(Value::Null));
    let merged = union(&local, &incoming);
    let added = merged.len() - local.len();
    plan.write("blocked.packages", json!(merged));
    // OR the switch with the local value so an imported enable is not lost.
    let enabled =
        boolean(current, "enabled").unwrap_or(false) || boolean(value, "enabled").unwrap_or(false);
    plan.write("blocked.enabled", json!(enabled));
    Ok(Outcome {
        added: added as u64,
        skipped: (incoming.len() - added) as u64,
        ..Outcome::new(Group::Blocked)
    })
}

pub fn allowlist(value: &Value, current: &Value, plan: &mut Plan) -> Result<Outcome, &'static str> {
    if !value.is_object() {
        return Err("appRulesNotObject");
    }
    let mut merged: Vec<(String, Vec<String>)> = Vec::new();
    if let Some(local) = get(current, "rules").and_then(as_object) {
        for (package, domains) in local {
            // Local domains are a list per package, not a list of lists.
            merged.push((package.clone(), string_set(domains)));
        }
    }

    let mut added = 0u64;
    if let Some(rules) = get(value, "rules").and_then(as_object) {
        for (package, domains) in rules {
            // Package names come from the file; blank ones cannot match an installed app.
            if package.trim().is_empty() {
                continue;
            }
            let incoming = string_set(domains);
            if incoming.is_empty() {
                continue;
            }
            match merged.iter_mut().find(|(key, _)| key == package) {
                Some((_, existing)) => {
                    let before = existing.len();
                    *existing = union(existing, &incoming);
                    added += (existing.len() - before) as u64;
                }
                None => {
                    added += incoming.len() as u64;
                    merged.push((package.clone(), incoming));
                }
            }
        }
    }

    merged.sort_by(|left, right| left.0.cmp(&right.0));
    let mut record = serde_json::Map::new();
    for (package, domains) in merged {
        record.insert(package, json!(domains));
    }
    plan.write("allowlist.rules", Value::Object(record));
    let enabled =
        boolean(current, "enabled").unwrap_or(false) || boolean(value, "enabled").unwrap_or(false);
    plan.write("allowlist.enabled", json!(enabled));
    Ok(Outcome {
        added,
        skipped: u64::from(added == 0),
        ..Outcome::new(Group::Allowlist)
    })
}

pub fn http_inspection(
    value: &Value,
    current: &Value,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    if !value.is_object() {
        return Err("inspectionNotObject");
    }
    let incoming = string_set(&get(value, "packages").cloned().unwrap_or(Value::Null));
    let local = string_set(&get(current, "packages").cloned().unwrap_or(Value::Null));
    let merged = union(&local, &incoming);
    let added = merged.len() - local.len();
    plan.write("httpInspection.packages", json!(merged));
    // Inspection is never enabled by an import: `https_inspection_ready` depends on a locally
    // installed CA, so enabling it would break HTTPS. Only the HTTP/3 switch travels.
    if let Some(http3) = boolean(value, "http3Enabled") {
        plan.write("httpInspection.http3", json!(http3));
    }
    Ok(Outcome {
        added: added as u64,
        skipped: (incoming.len() - added) as u64,
        ..Outcome::new(Group::HttpInspection)
    })
}
