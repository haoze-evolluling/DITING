//! Selected service ids → the rule patterns a blocking (or allow) group is built from.

use serde_json::Value;

use crate::catalog::{find, CATALOG};

/// One generated rule: the pattern a rule engine stores, the service it came from and the action.
struct Rule {
    pattern: String,
    service_id: &'static str,
    service_name: &'static str,
    kind: String,
}

/// Expands `service_ids` into rule patterns.
///
/// `kind` is `block` or `allow` (`allow` produces an exception group). For every domain of every
/// selected service the exact host and its wildcard sub-domain are emitted (`example.com`,
/// `*.example.com`), which is what the policy snapshot's suffix rules expect. An unknown id is
/// skipped rather than failing the whole expansion, so an older UI payload cannot break the
/// caller; the answered `unknown` list lets the caller surface it. Duplicates are removed while
/// preserving first-seen order.
pub fn expand(service_ids: &[String], kind: &str) -> Value {
    let kind = if kind == "allow" { "allow" } else { "block" };
    let mut rules: Vec<Rule> = Vec::new();
    let mut seen: Vec<String> = Vec::new();
    let mut unknown: Vec<String> = Vec::new();
    let mut resolved: Vec<&'static str> = Vec::new();

    for id in service_ids {
        let Some(service) = find(id) else {
            if !unknown.contains(id) {
                unknown.push(id.clone());
            }
            continue;
        };
        if !resolved.contains(&service.id) {
            resolved.push(service.id);
        }
        for domain in service.domains {
            for pattern in [domain.to_string(), format!("*.{domain}")] {
                if seen.contains(&pattern) {
                    continue;
                }
                seen.push(pattern.clone());
                rules.push(Rule {
                    pattern,
                    service_id: service.id,
                    service_name: service.name,
                    kind: kind.to_string(),
                });
            }
        }
    }

    let rules_json: Vec<Value> = rules
        .iter()
        .map(|rule| {
            serde_json::json!({
                "pattern": rule.pattern,
                "serviceId": rule.service_id,
                "serviceName": rule.service_name,
                "kind": rule.kind,
            })
        })
        .collect();
    serde_json::json!({
        "kind": kind,
        "services": resolved,
        "unknown": unknown,
        "rules": rules_json,
        "count": rules.len(),
    })
}

/// The number of catalog services, exposed so the UI can sanity check its own grouping.
pub fn catalog_size() -> usize {
    CATALOG.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn expands_both_host_and_wildcard() {
        let answer = expand(&ids(&["youtube"]), "block");
        assert_eq!(answer["count"], 8); // 4 domains * 2 patterns
        let patterns: Vec<String> = answer["rules"]
            .as_array()
            .unwrap()
            .iter()
            .map(|rule| rule["pattern"].as_str().unwrap().to_string())
            .collect();
        assert!(patterns.contains(&"youtube.com".to_string()));
        assert!(patterns.contains(&"*.youtube.com".to_string()));
        assert_eq!(answer["rules"][0]["kind"], "block");
    }

    #[test]
    fn deduplicates_and_orders_by_input() {
        // instagram has two domains → four patterns, no duplicates.
        let answer = expand(&ids(&["instagram"]), "block");
        assert_eq!(answer["count"], 4);
        let first = answer["rules"][0]["pattern"].as_str().unwrap();
        assert_eq!(first, "instagram.com");
    }

    #[test]
    fn unknown_ids_are_reported_not_fatal() {
        let answer = expand(&ids(&["youtube", "nope"]), "block");
        assert_eq!(answer["unknown"], serde_json::json!(["nope"]));
        assert!(answer["count"].as_u64().unwrap() > 0);
    }

    #[test]
    fn allow_kind_flows_through() {
        let answer = expand(&ids(&["steam"]), "allow");
        assert_eq!(answer["kind"], "allow");
        assert_eq!(answer["rules"][0]["kind"], "allow");
    }

    #[test]
    fn duplicate_service_ids_do_not_duplicate_rules() {
        let answer = expand(&ids(&["steam", "steam"]), "block");
        let count_once = expand(&ids(&["steam"]), "block")["count"].clone();
        assert_eq!(answer["count"], count_once);
    }

    #[test]
    fn empty_selection_is_empty() {
        let answer = expand(&[], "block");
        assert_eq!(answer["count"], 0);
        assert_eq!(answer["services"], serde_json::json!([]));
    }
}
