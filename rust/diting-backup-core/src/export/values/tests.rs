use serde_json::json;

use super::build;
use crate::groups::Group;

fn providers_selection() -> serde_json::Value {
    build(
        Group::Providers,
        &json!({
            "itemsJson": "[{\"id\":\"user_a\",\"name\":\"我的 DoH\",\"protocol\":\"DOH\"}]",
            "catalog": [
                {"id": "preset_ali", "name": "阿里", "protocol": "PLAIN"},
                {"id": "user_a", "name": "我的 DoH", "protocol": "DOH"},
            ],
            "selectedProviderId": "user_a",
            "resolutionMode": "smart",
            "presetDnsService": "ali",
            "raceTestDomain": "example.test",
            "raceProviderIds": ["preset_ali", "ghost"],
            "homeVisibleProtocols": ["DOH", "PLAIN", "DOH"],
        }),
    )
    .expect("providers")
}

#[test]
fn providers_keep_items_and_resolvable_selection() {
    let value = providers_selection();
    assert_eq!(value["items"].as_array().unwrap().len(), 1);
    let selection = &value["selection"];
    assert_eq!(selection["selectedProvider"]["name"], json!("我的 DoH"));
    assert_eq!(selection["selectedProvider"]["isPreset"], json!(false));
    // An unknown id still produces a reference: dropping it would hide a broken selection.
    assert_eq!(
        selection["raceProviderRefs"][1],
        json!({"id": "ghost", "name": "ghost", "protocol": "DOH", "isPreset": false})
    );
    assert_eq!(
        selection["raceProviderRefs"][0]["protocol"],
        json!("PLAIN"),
        "preset protocol must come from the catalog"
    );
    // Sorted and de-duplicated, so two equal backups are byte-identical.
    assert_eq!(
        selection["homeProviderVisibility"]["visibleProtocols"],
        json!(["DOH", "PLAIN"])
    );
}

#[test]
fn corrupt_local_json_is_reported_per_group() {
    assert_eq!(
        build(Group::Providers, &json!({"itemsJson": "["})).unwrap_err(),
        "providersInvalidJson"
    );
    assert_eq!(
        build(Group::Bootstrap, &json!({"customJson": "{"})).unwrap_err(),
        "bootstrapInvalidJson"
    );
    // Valid JSON of the wrong shape is not an error, just nothing to export.
    let value = build(Group::Providers, &json!({"itemsJson": "42"})).unwrap();
    assert_eq!(value["items"], json!([]));
    // Blank means "not set", not "corrupt".
    let value = build(Group::Bootstrap, &json!({"customJson": "  "})).unwrap();
    assert_eq!(value["custom"], json!(null));
}

#[test]
fn bootstrap_keeps_the_parsed_custom_document() {
    let value = build(
        Group::Bootstrap,
        &json!({
            "enabled": true,
            "presetIds": ["ali"],
            "customJson": "[{\"url\":\"https://d.test/dns-query\"}]",
        }),
    )
    .unwrap();
    assert_eq!(value["enabled"], json!(true));
    assert_eq!(value["presetIds"], json!(["ali"]));
    assert_eq!(value["custom"][0]["url"], json!("https://d.test/dns-query"));
}

#[test]
fn rules_turn_stored_ints_into_bools() {
    let value = build(
        Group::DomainRules,
        &json!({
            "block": [{"pattern": "a.test", "enabled": 0, "important": 1,
                       "appScope": "com.a", "appInverted": 1, "rawLine": "a.test",
                       "groupName": "我的"}],
            "allow": [{"pattern": "b.test"}],
        }),
    )
    .unwrap();
    let rules = value.as_array().unwrap();
    assert_eq!(rules.len(), 2);
    assert_eq!(rules[0]["kind"], json!("block"));
    assert_eq!(rules[0]["enabled"], json!(false));
    assert_eq!(rules[0]["important"], json!(true));
    assert_eq!(rules[0]["appInverted"], json!(true));
    assert_eq!(rules[0]["appScope"], json!("com.a"));
    assert_eq!(rules[0]["group"], json!("我的"));
    // Missing columns fall back to the table defaults (enabled, not important).
    assert_eq!(rules[1]["kind"], json!("allow"));
    assert_eq!(rules[1]["enabled"], json!(true));
    assert_eq!(rules[1]["important"], json!(false));
}

#[test]
fn rewrite_groups_split_one_table() {
    let source = json!({"rows": [
        {"pattern": "a.test", "targetType": "IPv4", "targetValue": "1.1.1.1", "enabled": 1},
        {"pattern": "b.test", "targetType": "IPv6", "targetValue": "::1"},
        {"pattern": "c.test", "targetType": "CNAME", "targetValue": "d.test"},
    ]});
    let domain = build(Group::RewriteDomain, &source).unwrap();
    assert_eq!(domain.as_array().unwrap().len(), 2);
    let cname = build(Group::RewriteCname, &source).unwrap();
    assert_eq!(cname.as_array().unwrap().len(), 1);
    assert_eq!(cname[0]["targetValue"], json!("d.test"));
}

#[test]
fn address_rules_keep_the_url_kind() {
    let value = build(
        Group::AddressRules,
        &json!({"rows": [{"pattern": "https://a.test", "kind": "url", "rawLine": "x"}]}),
    )
    .unwrap();
    assert_eq!(value[0]["kind"], json!("url"));
    assert_eq!(value[0]["enabled"], json!(true));
}

#[test]
fn subscriptions_name_groups_and_normalise_enums() {
    let value = build(
        Group::Subscriptions,
        &json!({
            "groups": [{"id": 7, "name": "订阅A", "autoUpdateEnabled": false}],
            "mirrorTemplates": [{"name": "m", "template": "https://{name}"}],
            "items": [
                {"url": "https://s.test/a.txt", "name": "A", "kind": "HOSTS",
                 "sourceType": "local", "enabled": 0, "groupId": 7,
                 "mirrorTemplate": "m", "mirrorFallback": 0},
                {"url": "https://s.test/b.txt", "name": "B", "kind": "nope",
                 "sourceType": "cloud", "groupId": 9},
            ],
        }),
    )
    .unwrap();
    let items = value["items"].as_array().unwrap();
    assert_eq!(items[0]["kind"], json!("hosts"));
    assert_eq!(items[0]["sourceType"], json!("local"));
    assert_eq!(items[0]["enabled"], json!(false));
    assert_eq!(items[0]["mirrorFallback"], json!(false));
    assert_eq!(items[0]["groupName"], json!("订阅A"));
    assert_eq!(items[0]["scope"], json!("dns"));
    // Unknown enum spells and dangling group ids never leak into the file.
    assert_eq!(items[1]["kind"], json!("domain"));
    assert_eq!(items[1]["sourceType"], json!("remote"));
    assert_eq!(items[1]["groupName"], json!(null));
    assert_eq!(items[1]["mirrorFallback"], json!(true));
    assert_eq!(
        value["mirrorTemplates"][0]["template"],
        json!("https://{name}")
    );
}

#[test]
fn outbound_never_carries_credentials() {
    let value = build(
        Group::Outbound,
        &json!({
            "enabled": true, "protocol": "socks5", "host": "h.test", "port": 1080,
            // A snapshot that still contains credentials must not leak them.
            "username": "u", "password": "p",
        }),
    )
    .unwrap();
    let record = value.as_object().unwrap();
    assert_eq!(record.get("credentialsExcluded"), Some(&json!(true)));
    assert!(!record.contains_key("username"));
    assert!(!record.contains_key("password"));
    assert_eq!(record.get("port"), Some(&json!(1080)));
}

#[test]
fn app_lists_are_sorted_and_deduplicated() {
    let value = build(
        Group::Excluded,
        &json!({"packages": ["com.b", "com.a", "com.b", " "]}),
    )
    .unwrap();
    assert_eq!(value, json!(["com.a", "com.b"]));
    let value = build(
        Group::Blocked,
        &json!({"enabled": true, "packages": ["com.b", "com.a"]}),
    )
    .unwrap();
    assert_eq!(value["enabled"], json!(true));
    assert_eq!(value["packages"], json!(["com.a", "com.b"]));
}

#[test]
fn allowlist_keeps_per_app_domains() {
    let value = build(
        Group::Allowlist,
        &json!({
            "enabled": false,
            "rules": {"com.a": ["b.test", "a.test"], "com.b": []},
        }),
    )
    .unwrap();
    assert_eq!(value["rules"]["com.a"], json!(["a.test", "b.test"]));
    assert_eq!(value["rules"]["com.b"], json!([]));
}

#[test]
fn http_inspection_never_invents_the_switch() {
    let value = build(
        Group::HttpInspection,
        &json!({"enabled": false, "http3Enabled": true, "packages": ["com.a"]}),
    )
    .unwrap();
    assert_eq!(value["enabled"], json!(false));
    assert_eq!(value["http3Enabled"], json!(true));
    assert_eq!(value["packages"], json!(["com.a"]));
}

#[test]
fn appearance_rounds_float_opacity() {
    let value = build(
        Group::Appearance,
        &json!({
            "themeMode": "dark",
            "componentOpacity": 0.800000011920929,
            "homePoemOpacity": 0.555,
            "hapticEnabled": true,
            "bottomBarIds": ["home", "settings"],
            "homeSentenceRunning": "跑着",
        }),
    )
    .unwrap();
    assert_eq!(value["componentOpacity"], json!(0.8));
    assert_eq!(value["homePoemOpacity"], json!(0.56));
    // A slider that was never moved falls back to the shared value, not to "fully opaque".
    assert_eq!(value["homeDnsDetailOpacity"], json!(0.8));
    assert_eq!(value["bottomBarIds"], json!(["home", "settings"]));
    assert_eq!(value["homeSentenceRunning"], json!("跑着"));
}

#[test]
fn system_keeps_traffic_defaults_and_the_nested_dynamic_block() {
    let value = build(
        Group::System,
        &json!({
            "bypassLan": true,
            "dynamicBlockResponse": {
                "enabled": true,
                "requestThreshold": 30,
                "windowSeconds": 60,
                "nxDomainDurationSeconds": 120,
            },
        }),
    )
    .unwrap();
    assert_eq!(value["bypassLan"], json!(true));
    // `app_traffic_stats_enabled` defaults to on and retention to 30 days.
    assert_eq!(value["appTrafficStatsEnabled"], json!(true));
    assert_eq!(value["trafficStatsRetentionDays"], json!(30));
    assert_eq!(value["trafficStatsHideSystemApps"], json!(false));
    assert_eq!(value["dynamicBlockResponse"]["enabled"], json!(true));
    assert_eq!(value["dynamicBlockResponse"]["windowSeconds"], json!(60));
    let value = build(Group::System, &json!({"appTrafficStatsEnabled": false})).unwrap();
    assert_eq!(value["appTrafficStatsEnabled"], json!(false));
}
