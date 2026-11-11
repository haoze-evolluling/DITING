//! Document reader: validate the envelope, merge every group against the local snapshot, and
//! answer with an import plan.
//!
//! Input  `{content, nowMs, hasDatabase, current: {<key>: <snapshot>}}`
//! Output `{fatal: {kind, detail} | null, exportedAt, outcomes: [{group, added, skipped,
//!          updated, error}], writes: [{field, value}], ops: [op], subscriptionCount}`
//!
//! The plan is split on purpose: a `write` is one settings field the app should store, an `op` is
//! one statement against the rule database. Both are unconditional — every decision (merge, dedupe,
//! counters, clamps) happens here, so the app cannot drift from the backup semantics.

use serde_json::{json, Map, Value};

use crate::export::{check_envelope, present_groups};
use crate::groups::Group;
use crate::value::{as_object, get, integer};

mod lists;
mod prefs;
mod rules;
mod settings;

/// One settings field to store, or one database statement to run.
#[derive(Default)]
pub struct Plan {
    pub writes: Vec<Value>,
    pub ops: Vec<Value>,
}

impl Plan {
    pub fn write(&mut self, field: &str, value: Value) {
        self.writes.push(json!({"field": field, "value": value}));
    }

    pub fn op(&mut self, op: Value) {
        self.ops.push(op);
    }
}

pub struct Outcome {
    pub group: Group,
    pub added: u64,
    pub skipped: u64,
    pub updated: u64,
    pub error: Option<&'static str>,
}

impl Outcome {
    pub fn new(group: Group) -> Self {
        Self {
            group,
            added: 0,
            skipped: 0,
            updated: 0,
            error: None,
        }
    }

    pub fn failed(group: Group, error: &'static str) -> Self {
        Self {
            error: Some(error),
            ..Self::new(group)
        }
    }

    fn to_value(&self) -> Value {
        json!({
            "group": self.group.key(),
            "added": self.added,
            "skipped": self.skipped,
            "updated": self.updated,
            "error": self.error,
        })
    }
}

pub fn run(input: &Value) -> Value {
    let content = get(input, "content")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let now = integer(input, "nowMs").unwrap_or(0);
    let has_database = get(input, "hasDatabase")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let current = get(input, "current").cloned().unwrap_or(Value::Null);

    let record = match check_envelope(content) {
        Ok(record) => record,
        Err(envelope) => {
            return json!({"fatal": {"kind": envelope.kind(), "detail": envelope.detail()}});
        }
    };

    let exported_at = match record.get("exportedAt") {
        Some(Value::Number(number)) => Value::from(number.as_i64().unwrap_or_default()),
        _ => Value::Null,
    };
    let data = record
        .get("data")
        .and_then(as_object)
        .cloned()
        .unwrap_or_default();

    let mut plan = Plan::default();
    let mut outcomes = Vec::new();
    let mut subscription_count = 0;

    for group in present_groups(&data) {
        let value = data.get(group.key()).cloned().unwrap_or(Value::Null);
        let snapshot = get(&current, group.key()).cloned().unwrap_or(Value::Null);
        match apply(group, &value, &snapshot, now, has_database, &mut plan) {
            Ok(outcome) => {
                if group == Group::Subscriptions {
                    // Used to ask the user to refresh the imported subscriptions.
                    subscription_count = outcome.added;
                }
                outcomes.push(outcome);
            }
            // A group that cannot be applied is reported; the rest of the file still lands.
            Err(kind) => outcomes.push(Outcome::failed(group, kind)),
        }
    }

    json!({
        "fatal": Value::Null,
        "exportedAt": exported_at,
        "outcomes": outcomes.iter().map(Outcome::to_value).collect::<Vec<_>>(),
        "writes": plan.writes,
        "ops": plan.ops,
        "subscriptionCount": subscription_count,
    })
}

fn apply(
    group: Group,
    value: &Value,
    current: &Value,
    now: i64,
    has_database: bool,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    Ok(match group {
        Group::Providers => prefs::providers(value, current, plan),
        Group::Bootstrap => prefs::bootstrap(value, current, plan),
        Group::Cache => prefs::cache(value, current, plan),
        Group::Outbound => prefs::outbound(value, current, plan),
        Group::Subscriptions => rules::subscriptions(value, current, now, has_database, plan)?,
        Group::DomainRules => rules::domain_rules(value, current, now, has_database, plan)?,
        Group::RewriteDomain | Group::RewriteCname => {
            rules::rewrite(group, value, current, now, has_database, plan)?
        }
        Group::AddressRules => rules::address_rules(value, current, now, has_database, plan)?,
        Group::Excluded => lists::excluded(value, current, plan),
        Group::Blocked => lists::blocked(value, current, plan)?,
        Group::Allowlist => lists::allowlist(value, current, plan)?,
        Group::HttpInspection => lists::http_inspection(value, current, plan)?,
        Group::Appearance => settings::appearance(value, current, plan)?,
        Group::System => settings::system(value, current, now, plan)?,
    })
}

/// `_stringSet`: trimmed, non-empty strings from a list or an object's keys.
pub fn string_set(value: &Value) -> Vec<String> {
    let mut values: Vec<String> = crate::value::string_set(value).into_keys().collect();
    values.sort();
    values
}

/// Union of the local set and the incoming one: an import never removes entries.
pub fn union(local: &[String], incoming: &[String]) -> Vec<String> {
    let mut merged: Vec<String> = local.to_vec();
    for value in incoming {
        if !merged.contains(value) {
            merged.push(value.clone());
        }
    }
    merged.sort();
    merged
}

pub fn same_order(left: &[String], right: &[String]) -> bool {
    left == right
}

/// Array of strings from a JSON list, keeping every `String` in order (including blanks), matching
/// `[for (final id in list) if (id is String) id]`.
pub fn strings(value: &Value) -> Vec<String> {
    match value {
        Value::Array(items) => items
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
        _ => Vec::new(),
    }
}

/// `item is Map` check for document entries.
pub fn as_record(value: &Value) -> Option<&Map<String, Value>> {
    value.as_object()
}

/// Text that must be a non-blank string, trimmed (`_text`).
pub fn text_field(value: &Value, key: &str) -> Option<String> {
    crate::value::trimmed(value, key)
}

#[cfg(test)]
#[path = "import/tests.rs"]
mod tests;
