use serde_json::json;

use super::{rule_from_joined, rule_from_sources};

fn names() -> std::collections::BTreeMap<i64, String> {
    let mut names = std::collections::BTreeMap::new();
    names.insert(4, String::from("订阅A"));
    names
}

#[test]
fn a_rule_is_active_only_when_row_and_source_agree() {
    let joined = vec![
        json!({"id": 9, "pattern": "a.test", "enabled": 1, "important": 1,
               "groupName": "我的", "appScope": " com.a ",
               "sourceName": "sub_4", "sourceEnabled": 0}),
        json!({"id": 9, "pattern": "a.test", "enabled": 1, "important": 1,
               "groupName": "我的", "appScope": " com.a ",
               "sourceName": "useradd", "sourceEnabled": 0}),
    ];
    let rules = rule_from_joined("block", &joined, &names());
    assert_eq!(rules.len(), 1, "consecutive rows of one id are one rule");
    let rule = &rules[0];
    // Every source is disabled, so the rule is off even though its own flag is set.
    assert_eq!(rule["enabled"], json!(false));
    assert_eq!(rule["important"], json!(true));
    assert_eq!(rule["group"], json!("我的"));
    // `appScope` is trimmed; an empty value would be global.
    assert_eq!(rule["appScope"], json!("com.a"));
    assert_eq!(rule["source"], json!("subscription"));
    assert_eq!(rule["subscriptionName"], json!("订阅A"));
    assert_eq!(rule["id"], json!("9"));
}

#[test]
fn a_rule_without_sources_is_judged_by_its_own_flag() {
    let joined = vec![json!({"id": 3, "pattern": "*", "enabled": 0, "sourceName": null})];
    let rules = rule_from_joined("block", &joined, &names());
    assert_eq!(rules[0]["enabled"], json!(false));
    assert_eq!(rules[0]["source"], json!("user"));
    assert_eq!(rules[0]["subscriptionName"], json!(null));
}

#[test]
fn preset_provenance_wins_over_a_subscription() {
    let joined = vec![
        json!({"id": 1, "pattern": "a.test", "enabled": 1, "sourceName": "sub_4",
               "sourceEnabled": 1}),
        json!({"id": 1, "pattern": "a.test", "enabled": 1, "sourceName": "preset",
               "sourceEnabled": 1}),
    ];
    let rules = rule_from_joined("allow", &joined, &names());
    assert_eq!(rules[0]["source"], json!("preset"));
}

#[test]
fn a_deleted_subscription_leaves_the_rule_user_owned() {
    let joined = vec![json!({"id": 7, "pattern": "a.test", "enabled": 1,
                             "sourceName": "sub_99", "sourceEnabled": 1})];
    let rules = rule_from_joined("block", &joined, &names());
    // The source tag still points at a subscription, but its name is gone.
    assert_eq!(rules[0]["source"], json!("subscription"));
    assert_eq!(rules[0]["subscriptionName"], json!(null));
}

#[test]
fn rewrite_rules_take_their_target_and_drop_block_only_flags() {
    let joined = vec![
        json!({"id": 5, "pattern": "a.test", "enabled": 1, "important": 1,
                             "appInverted": 1, "targetValue": "1.1.1.1",
                             "sourceName": "useradd", "sourceEnabled": 1}),
    ];
    let rules = rule_from_joined("rewrite", &joined, &names());
    assert_eq!(rules[0]["target"], json!("1.1.1.1"));
    // `important` / `appInverted` have no column meaning for a rewrite row.
    assert_eq!(rules[0]["important"], json!(false));
    assert_eq!(rules[0]["appInverted"], json!(false));
    assert!(rules[0]["target"].is_string());
}

#[test]
fn split_rows_group_sources_by_rule_id() {
    let rules_rows = vec![
        json!({"id": 20, "pattern": "b.test", "enabled": 1}),
        json!({"id": 10, "pattern": "a.test", "enabled": 1}),
    ];
    let source_rows = vec![
        json!({"ruleId": 10, "source": "useradd", "enabled": 0}),
        json!({"ruleId": 20, "source": "useradd", "enabled": 1}),
    ];
    let rules = rule_from_sources("block", &rules_rows, &source_rows, &names());
    // The order of the query is preserved; only the flags differ.
    assert_eq!(rules[0]["pattern"], json!("b.test"));
    assert_eq!(rules[0]["enabled"], json!(true));
    assert_eq!(rules[1]["pattern"], json!("a.test"));
    assert_eq!(rules[1]["enabled"], json!(false));
}
