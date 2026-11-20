use std::sync::{Arc, RwLock};

use diting_dns_core::RewriteTable;
use diting_policy_core::json::RuleSnapshot;
use diting_policy_core::Snapshot;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Verdict {
    pub blocked: bool,
    pub reason: String,
}

#[derive(Default)]
pub struct Policy {
    snapshot: RwLock<Option<Arc<Snapshot>>>,
}

impl Policy {
    pub fn apply(&self, payload: &str) -> String {
        let request = match RuleSnapshot::parse(payload.as_bytes()) {
            Ok(request) => request,
            Err(error) => return error,
        };
        let snapshot = Snapshot::build(&request);
        *self.write() = Some(Arc::new(snapshot));
        String::new()
    }

    pub fn has_rules(&self) -> bool {
        match self.read().as_ref() {
            Some(snapshot) => snapshot.flags() & 1 != 0,
            None => false,
        }
    }

    pub fn is_active(&self) -> bool {
        self.read().is_some()
    }

    pub fn filtering_active(&self) -> bool {
        match self.read().as_ref() {
            Some(snapshot) => snapshot.filtering_active(),
            None => false,
        }
    }

    pub fn evaluate(&self, domain: &str, app_name: &str, qtype: u16) -> Option<Verdict> {
        let snapshot = self.read().clone()?;
        let answer = snapshot.answer(domain, app_name, qtype);
        Some(Verdict {
            blocked: answer.blocked,
            reason: answer.reason.as_str().to_string(),
        })
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, Option<Arc<Snapshot>>> {
        self.snapshot
            .read()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, Option<Arc<Snapshot>>> {
        self.snapshot
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

#[derive(Default)]
pub struct Rewrites {
    table: RwLock<Arc<RewriteTable>>,
}

impl Rewrites {
    pub fn publish(&self, table: RewriteTable) {
        *self
            .table
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Arc::new(table);
    }

    pub fn lookup(&self, domain: &str) -> Option<diting_config_core::rewrite::Entry> {
        let table = self
            .table
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        table.lookup(domain).cloned()
    }

    pub fn len(&self) -> usize {
        self.table
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

pub fn rewrites_from_json(payload: &str) -> Result<Vec<(String, Vec<String>)>, String> {
    let document: std::collections::BTreeMap<String, serde_json::Value> =
        serde_json::from_str(payload)
            .map_err(|error| format!("SetRewriteRules: invalid JSON: {error}"))?;

    let mut entries = Vec::with_capacity(document.len());
    for (domain, value) in document {
        let targets = match value {
            serde_json::Value::String(target) => vec![target],
            serde_json::Value::Array(items) => {
                let mut targets = Vec::with_capacity(items.len());
                let mut valid = true;
                for item in items {
                    match item {
                        serde_json::Value::String(target) => targets.push(target),
                        _ => {
                            valid = false;
                            break;
                        }
                    }
                }
                if !valid {
                    continue;
                }
                targets
            }
            _ => continue,
        };
        entries.push((domain, targets));
    }
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rewrite_payload_accepts_strings_and_arrays() {
        let entries = rewrites_from_json(
            r#"{"example.test":"1.2.3.4","other.test":["5.6.7.8","::1","alias.test"],"bad.test":7}"#,
        )
        .expect("decodes");
        assert_eq!(entries.len(), 2, "the non-string value is dropped");
        assert_eq!(entries[0], ("example.test".into(), vec!["1.2.3.4".into()]));
        assert_eq!(entries[1].1.len(), 3);
    }

    #[test]
    fn rewrite_payload_reports_invalid_json() {
        let error = rewrites_from_json("{").expect_err("invalid");
        assert!(
            error.starts_with("SetRewriteRules: invalid JSON: "),
            "{error}"
        );
    }

    #[test]
    fn rewrites_look_up_parent_suffixes() {
        let rewrites = Rewrites::default();
        let entries = rewrites_from_json(r#"{"example.test":"1.2.3.4"}"#).expect("decodes");
        rewrites.publish(RewriteTable::build(&entries));
        let entry = rewrites.lookup("www.example.test").expect("suffix match");
        assert_eq!(entry.ip4, "1.2.3.4");
        assert!(rewrites.lookup("example.org").is_none());
    }

    #[test]
    fn policy_without_a_snapshot_has_no_rules() {
        let policy = Policy::default();
        assert!(!policy.has_rules());
        assert!(!policy.is_active());
        assert!(policy.evaluate("example.test", "", 1).is_none());
    }
}
