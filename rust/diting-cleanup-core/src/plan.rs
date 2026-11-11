//! The static catalog. Keys mirror the Dart `CleanupAction` names so a missing action fails loudly
//! in `CleanupPlan.action` instead of silently cleaning nothing.

use serde_json::{json, Value};

fn actions() -> Value {
    json!({
        "logs": { "exitsApp": false, "affectsEngine": false },
        "traffic": { "exitsApp": false, "affectsEngine": false },
        "crash": { "exitsApp": false, "affectsEngine": false },
        "dnsCache": { "exitsApp": false, "affectsEngine": false },
        "providerWeights": { "exitsApp": false, "affectsEngine": false },
        "bootstrapWeights": { "exitsApp": false, "affectsEngine": false },
        "domainRules": { "exitsApp": false, "affectsEngine": true },
        "addressRules": { "exitsApp": false, "affectsEngine": true },
        "subscriptions": { "exitsApp": false, "affectsEngine": true },
        "appRules": { "exitsApp": false, "affectsEngine": true },
        "outboundProxy": { "exitsApp": false, "affectsEngine": true },
        "caCertificate": { "exitsApp": false, "affectsEngine": false },
        "downloadCache": { "exitsApp": false, "affectsEngine": false },
        "customBackground": { "exitsApp": false, "affectsEngine": false },
        "settingsGuides": { "exitsApp": true, "affectsEngine": false },
        "allData": { "exitsApp": true, "affectsEngine": false },
    })
}

fn rule_pairs() -> Value {
    json!([
        { "table": "block_rule", "sourceTable": "block_rule_source" },
        { "table": "allow_rule", "sourceTable": "allow_rule_source" },
        { "table": "rewrite_rule", "sourceTable": "rewrite_rule_source" },
        { "table": "go_url_rule", "sourceTable": "go_url_rule_source" },
        { "table": "cosmetic_rule", "sourceTable": "cosmetic_rule_source" },
    ])
}

/// The complete document; a fresh `Value` per call so the FFI layer never hands out shared state.
pub fn plan() -> Value {
    json!({
        "actions": actions(),
        "logs": {
            "tables": ["dns_log", "http_request_log", "dns_race_log", "bootstrap_log"],
        },
        "traffic": { "table": "app_traffic_daily" },
        "dnsCache": { "table": "dns_cache" },
        "weights": {
            "containers": [
                "dns_vpn_prefs",
                "diting_express_prefs",
                "diting_dns_mode_prefs",
            ],
            "providerKey": "provider_health_json",
            "bootstrapKey": "bootstrap_health_json",
        },
        "domainRules": {
            "clearPairs": [
                { "table": "block_rule", "sourceTable": "block_rule_source" },
                { "table": "allow_rule", "sourceTable": "allow_rule_source" },
            ],
            "rewriteTable": "rewrite_rule",
            "rewriteSourceTable": "rewrite_rule_source",
            "rewriteWhere": "targetType IN ('IPv4','IPv6')",
            "cosmeticTables": ["cosmetic_rule_source", "cosmetic_rule"],
            "subscriptionTable": "subscription",
            "subscriptionWhere": "kind = 'domain'",
            "subscriptionReset": {
                "table": "subscription",
                "values": {
                    "ruleCount": 0,
                    "lastUpdated": 0,
                    "httpEtag": null,
                    "httpLastModified": null,
                    "ruleSetHash": null,
                },
            },
            "autoUpdateOrphans": {
                "table": "subscription_auto_update_item",
                "where": "subscriptionId NOT IN (SELECT id FROM subscription)",
            },
            "seedPresetOnMain": true,
        },
        "addressRules": {
            "clearPairs": [
                { "table": "go_url_rule", "sourceTable": "go_url_rule_source" },
            ],
            "rewriteTable": "rewrite_rule",
            "rewriteSourceTable": "rewrite_rule_source",
            "rewriteWhere": "targetType = 'CNAME'",
        },
        "subscriptions": {
            "tables": [
                "subscription",
                "subscription_group",
                "subscription_auto_update_item",
            ],
            "rulePairs": rule_pairs(),
            "sourceWhere": "source GLOB 'sub_*' OR source GLOB 'staging_sub_*'",
        },
        "appRules": {
            "container": "dns_vpn_prefs",
            "keys": [
                "excluded_app_packages",
                "blocked_app_packages",
                "blocked_apps_enabled",
                "app_allowlist_rules_json",
                "app_allowlist_enabled",
                "http_inspection_app_packages",
                "http_inspection_enabled",
            ],
            "readyKey": "https_inspection_ready",
        },
        "customBackground": {
            "container": "dns_vpn_prefs",
            "keys": [
                "custom_background_enabled",
                "custom_background_uri",
                "custom_background_uris",
            ],
        },
        "settingsGuides": {
            "container": "dns_vpn_prefs",
            "keys": [
                "settings_guide_acknowledged_ids",
                "initial_agreement_accepted",
            ],
            "dismissedContainer": "mode_permission_preferences",
            "dismissedPrefix": "recommendation_dismissed_",
        },
        "allData": {
            "order": [
                "logs",
                "traffic",
                "crash",
                "dnsCache",
                "providerWeights",
                "bootstrapWeights",
                "domainRules",
                "addressRules",
                "subscriptions",
                "appRules",
                "outboundProxy",
                "caCertificate",
                "downloadCache",
                "customBackground",
                "settingsGuides",
            ],
            "tables": ["mirror_template"],
            "prefs": [
                { "container": "recognition_members", "key": "members" },
            ],
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings<'a>(value: &'a Value, key: &str) -> Vec<&'a str> {
        value[key]
            .as_array()
            .unwrap()
            .iter()
            .map(|item| item.as_str().unwrap())
            .collect()
    }

    #[test]
    fn every_action_has_flags() {
        let actions = plan()["actions"].as_object().unwrap().clone();
        assert_eq!(actions.len(), 16);
        for (name, flags) in actions {
            assert!(flags["exitsApp"].is_boolean(), "{name}");
            assert!(flags["affectsEngine"].is_boolean(), "{name}");
        }
    }

    #[test]
    fn log_and_cache_tables_follow_the_legacy_order() {
        let plan = plan();
        assert_eq!(
            strings(&plan["logs"], "tables"),
            [
                "dns_log",
                "http_request_log",
                "dns_race_log",
                "bootstrap_log"
            ]
        );
        assert_eq!(plan["traffic"]["table"], "app_traffic_daily");
        assert_eq!(plan["dnsCache"]["table"], "dns_cache");
    }

    #[test]
    fn domain_clears_drop_cname_and_keep_address_rules() {
        let plan = plan();
        let pairs = plan["domainRules"]["clearPairs"].as_array().unwrap();
        assert_eq!(pairs.len(), 2);
        assert_eq!(pairs[0]["table"], "block_rule");
        assert_eq!(pairs[1]["sourceTable"], "allow_rule_source");
        assert_eq!(
            plan["domainRules"]["rewriteWhere"],
            "targetType IN ('IPv4','IPv6')"
        );
        assert_eq!(plan["addressRules"]["rewriteWhere"], "targetType = 'CNAME'");
        assert_eq!(
            plan["subscriptions"]["rulePairs"].as_array().unwrap().len(),
            5
        );
    }

    #[test]
    fn all_data_order_ends_with_guides_and_clears_mirror_and_recognition() {
        let plan = plan();
        let order = strings(&plan["allData"], "order");
        assert_eq!(*order.last().unwrap(), "settingsGuides");
        assert_eq!(order.len(), 15);
        assert_eq!(strings(&plan["allData"], "tables"), ["mirror_template"]);
        assert_eq!(
            plan["allData"]["prefs"][0]["container"],
            "recognition_members"
        );
    }

    #[test]
    fn action_flags_match_the_switch() {
        let plan = plan();
        assert!(plan["actions"]["settingsGuides"]["exitsApp"]
            .as_bool()
            .unwrap());
        assert!(plan["actions"]["allData"]["exitsApp"].as_bool().unwrap());
        assert!(plan["actions"]["subscriptions"]["affectsEngine"]
            .as_bool()
            .unwrap());
        assert!(!plan["actions"]["logs"]["affectsEngine"].as_bool().unwrap());
    }
}
