//! Serde model of the rule snapshot payload `ApplyRuleSnapshot` receives from Dart.
//!
//! Field names, optionality and `null` handling mirror `ruleSnapshotJSON` in
//! `android/engine/policy_engine.go`, because the Go engine stays the reference implementation and
//! both sides have to read the same document.
//!
//! Every collection is `Option`-aligned with Go's nil slices/maps: `null`, a missing key and an
//! empty array all end up meaning "no rules", exactly like `encoding/json` leaves the zero value.

use serde::Deserialize;

/// `appRulesConfigJSON`.
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppRules {
    pub allow: Option<Vec<String>>,
    pub block: Option<Vec<String>>,
    pub important: Option<Vec<String>>,
}

/// `invertedRuleConfigJSON`.
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InvertedRule {
    pub pattern: Option<String>,
    pub source: Option<String>,
    pub important: Option<bool>,
    pub excluded_apps: Option<Vec<String>>,
}

/// `specialRuleConfigJSON`.
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecialRule {
    pub pattern: Option<String>,
    pub source: Option<String>,
    pub important: Option<bool>,
    pub app_scope: Option<String>,
    pub app_inverted: Option<bool>,
    pub is_wildcard: Option<bool>,
    pub denyallow: Option<String>,
    pub is_regex: Option<bool>,
    pub dns_type: Option<String>,
}

/// `ruleSnapshotJSON`.
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleSnapshot {
    pub filter_enabled: Option<bool>,
    pub block_trie_path: Option<String>,
    pub important_block_trie_path: Option<String>,
    pub allow_trie_path: Option<String>,
    pub important_allow_trie_path: Option<String>,
    pub global_allow: Option<Vec<String>>,
    pub global_block: Option<Vec<String>>,
    pub global_important: Option<Vec<String>>,
    pub app_rules: Option<std::collections::HashMap<String, AppRules>>,
    pub inverted_block: Option<Vec<InvertedRule>>,
    pub inverted_allow: Option<Vec<InvertedRule>>,
    pub special_block: Option<Vec<SpecialRule>>,
    pub special_allow: Option<Vec<SpecialRule>>,
    pub disabled_rules: Option<Vec<String>>,
}

impl RuleSnapshot {
    /// Parses the payload; the error text is only used for logging on the Go side.
    pub fn parse(bytes: &[u8]) -> Result<RuleSnapshot, String> {
        serde_json::from_slice(bytes).map_err(|error| error.to_string())
    }

    pub fn strings<'a>(&self, field: &'a Option<Vec<String>>) -> &'a [String] {
        field.as_deref().unwrap_or(&[])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_documented_shape() {
        let json = br#"{
            "filterEnabled": true,
            "blockTriePath": "/tmp/block.dtri",
            "globalBlock": ["a.com", "*.b.com"],
            "appRules": {"com.a": {"allow": ["x.com"], "block": [], "important": null}},
            "specialBlock": [{"pattern": "^ad\\d+$", "isRegex": true, "dnsType": "~AAAA"}],
            "invertedAllow": [{"pattern": "keep.com", "excludedApps": ["com.a"]}],
            "disabledRules": ["off.com"]
        }"#;
        let snapshot = RuleSnapshot::parse(json).expect("parse");
        assert_eq!(snapshot.filter_enabled, Some(true));
        assert_eq!(snapshot.block_trie_path.as_deref(), Some("/tmp/block.dtri"));
        assert_eq!(snapshot.strings(&snapshot.global_block).len(), 2);
        let bucket = &snapshot.app_rules.as_ref().unwrap()["com.a"];
        assert_eq!(bucket.allow.as_ref().unwrap().len(), 1);
        assert!(bucket.important.is_none());
        assert_eq!(snapshot.special_block.as_ref().unwrap().len(), 1);
        assert_eq!(
            snapshot.inverted_allow.as_ref().unwrap()[0]
                .excluded_apps
                .as_ref()
                .unwrap()[0],
            "com.a"
        );
    }

    #[test]
    fn null_collections_parse_like_go_nil_slices() {
        let snapshot =
            RuleSnapshot::parse(br#"{"globalBlock": null, "appRules": null}"#).expect("parse");
        assert!(snapshot.strings(&snapshot.global_block).is_empty());
        assert!(snapshot.app_rules.is_none());
    }

    #[test]
    fn unknown_fields_are_ignored_like_encoding_json() {
        assert!(RuleSnapshot::parse(br#"{"somethingElse": 1, "filterEnabled": false}"#).is_ok());
    }

    #[test]
    fn a_wrong_type_is_an_error() {
        assert!(RuleSnapshot::parse(br#"{"globalBlock": 3}"#).is_err());
    }
}
