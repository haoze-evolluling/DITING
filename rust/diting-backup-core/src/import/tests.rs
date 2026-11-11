use serde_json::{json, Value};

use crate::export;
use crate::import;

/// One exported document, as the app would hand it back for import.
fn document(groups: &[&str], fields: Value) -> String {
    let output = export::run(&json!({
        "nowMs": 1_700_000_000_000i64,
        "groups": groups,
        "fields": fields,
    }));
    output["content"].as_str().unwrap().to_string()
}

fn run_import(content: &str, current: Value, has_database: bool) -> Value {
    import::run(&json!({
        "content": content,
        "nowMs": 2000,
        "hasDatabase": has_database,
        "current": current,
    }))
}

fn write_of<'a>(plan: &'a Value, field: &str) -> Option<&'a Value> {
    plan["writes"]
        .as_array()?
        .iter()
        .find(|write| write["field"] == json!(field))
        .map(|write| &write["value"])
}

fn outcome_of<'a>(plan: &'a Value, group: &str) -> &'a Value {
    plan["outcomes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|outcome| outcome["group"] == json!(group))
        .expect("outcome for group")
}

#[test]
fn a_fatal_envelope_reports_no_outcomes() {
    let plan = run_import("hello", json!({}), false);
    assert_eq!(plan["fatal"]["kind"], json!("notJson"));
    assert_eq!(plan["outcomes"], json!(null));

    let plan = run_import(
        "{\"format\":\"diting-backup\",\"version\":99,\"data\":{}}",
        json!({}),
        false,
    );
    assert_eq!(plan["fatal"]["kind"], json!("tooNew"));
    assert_eq!(plan["fatal"]["detail"], json!(99));
}

#[test]
fn a_missing_database_fails_the_rule_groups_only() {
    let content = document(
        &["domainRules", "excluded"],
        json!({
            "domainRules": {"block": [{"pattern": "a.test"}], "allow": []},
            "excluded": {"packages": ["com.a"]},
        }),
    );
    let plan = run_import(&content, json!({}), false);
    assert_eq!(
        outcome_of(&plan, "domainRules")["error"],
        json!("noDbRules")
    );
    assert_eq!(outcome_of(&plan, "excluded")["added"], json!(1));
    assert_eq!(plan["ops"], json!([]));
}

#[test]
fn exported_at_travels_with_the_document() {
    let content = document(&["excluded"], json!({"excluded": {"packages": ["com.a"]}}));
    let plan = run_import(&content, json!({}), false);
    assert_eq!(plan["exportedAt"], json!(1_700_000_000_000i64));
}

#[test]
fn rules_are_deduped_by_pattern_important_and_scope() {
    let content = document(
        &["domainRules"],
        json!({
            "domainRules": {
                "block": [
                    {"pattern": "a.test", "important": 1, "appScope": "com.a", "rawLine": "a.test"},
                    {"pattern": "a.test", "important": 0, "rawLine": "a.test"},
                ],
                "allow": [],
            },
        }),
    );
    // The local device already has the global rule but not the per-app one.
    let current = json!({
        "domainRules": {"block": [{"pattern": "a.test", "important": 0, "appScope": null}]},
    });
    let plan = run_import(&content, current, true);
    let outcome = outcome_of(&plan, "domainRules");
    assert_eq!(outcome["added"], json!(1));
    assert_eq!(outcome["skipped"], json!(1));
    let ops = plan["ops"].as_array().unwrap();
    assert_eq!(ops.len(), 1);
    assert_eq!(ops[0]["table"], json!("block_rule"));
    assert_eq!(ops[0]["row"]["appScope"], json!("com.a"));
    assert_eq!(ops[0]["row"]["important"], json!(1));
    assert_eq!(ops[0]["row"]["isWildcard"], json!(0));
    assert_eq!(ops[0]["row"]["addedAt"], json!(2000));

    // Re-running the same file against the freshly merged state adds nothing.
    let current = json!({
        "domainRules": {"block": [
            {"pattern": "a.test", "important": 0, "appScope": null},
            {"pattern": "a.test", "important": 1, "appScope": "com.a"},
        ]},
    });
    let again = run_import(&content, current, true);
    assert_eq!(outcome_of(&again, "domainRules")["added"], json!(0));
    assert_eq!(again["ops"], json!([]));
}

#[test]
fn rewrite_same_pattern_with_a_new_value_is_an_update() {
    let content = document(
        &["rewriteDomain"],
        json!({"rewriteDomain": {"rows": [
            {"pattern": "r.test", "targetType": "IPv4", "targetValue": "1.1.1.1",
             "rawLine": "r.test 1.1.1.1"},
        ]}}),
    );
    let current = json!({"rewriteDomain": {"rows": [
        {"id": 4, "pattern": "r.test", "targetType": "IPv4", "targetValue": "9.9.9.9"},
    ]}});
    let plan = run_import(&content, current, true);
    let outcome = outcome_of(&plan, "rewriteDomain");
    assert_eq!(outcome["updated"], json!(1));
    let ops = plan["ops"].as_array().unwrap();
    assert_eq!(ops[0]["op"], json!("rewriteUpdate"));
    assert_eq!(ops[0]["id"], json!(4));
    assert_eq!(ops[0]["targetValue"], json!("1.1.1.1"));
    assert_eq!(ops[0]["rawLine"], json!("r.test 1.1.1.1"));
}

#[test]
fn a_rewrite_group_only_takes_its_own_target_types() {
    // `rewriteCname` is absent from the file, so its rows must not sneak in through the IPv4 group.
    let content = document(
        &["rewriteDomain"],
        json!({"rewriteDomain": {"rows": [
            {"pattern": "c.test", "targetType": "CNAME", "targetValue": "d.test"},
        ]}}),
    );
    let plan = run_import(&content, json!({}), true);
    // The exported group is empty, so the import has nothing to skip.
    assert_eq!(outcome_of(&plan, "rewriteDomain")["skipped"], json!(0));
    assert_eq!(plan["ops"], json!([]));
}

#[test]
fn subscriptions_import_the_address_only_and_dedupe_by_url_and_kind() {
    let content = document(
        &["subscriptions"],
        json!({"subscriptions": {
            "groups": [{"id": 7, "name": "订阅A", "autoUpdateEnabled": false}],
            "mirrorTemplates": [{"name": "m", "template": "https://{name}"}],
            "items": [
                {"url": "https://s.test/a.txt", "name": "A", "kind": "domain", "groupId": 7},
                {"url": "https://s.test/a.txt", "name": "A 副本", "kind": "domain", "groupId": 7},
            ],
        }}),
    );
    let current = json!({"subscriptions": {"groupNames": ["订阅A"], "urls": []}});
    let plan = run_import(&content, current, true);
    let outcome = outcome_of(&plan, "subscriptions");
    // The group already exists; only the first item is new, the second one is a duplicate.
    assert_eq!(outcome["added"], json!(1));
    assert_eq!(outcome["skipped"], json!(2));
    assert_eq!(plan["subscriptionCount"], json!(1));
    let ops = plan["ops"].as_array().unwrap();
    let item = ops
        .iter()
        .find(|op| op["op"] == json!("subsItem"))
        .expect("subscription insert");
    assert_eq!(item["groupName"], json!("订阅A"));
    // Count, timestamp and ETag start empty so the first refresh downloads.
    assert_eq!(item["ruleCount"], json!(0));
    assert_eq!(item["lastUpdated"], json!(0));
    assert_eq!(item["addedAt"], json!(2000));
    let mirror = ops
        .iter()
        .find(|op| op["op"] == json!("subsMirror"))
        .expect("mirror template");
    assert_eq!(mirror["template"], json!("https://{name}"));
}

#[test]
fn a_new_group_is_created_before_its_subscriptions() {
    let content = document(
        &["subscriptions"],
        json!({"subscriptions": {
            "groups": [{"name": "新组", "autoUpdateEnabled": true}],
            "items": [{"url": "https://s.test/a.txt", "groupName": "新组"}],
        }}),
    );
    let plan = run_import(&content, json!({"subscriptions": {"groupNames": []}}), true);
    let ops = plan["ops"].as_array().unwrap();
    assert_eq!(ops[0]["op"], json!("subsGroup"));
    assert_eq!(ops[0]["autoUpdateEnabled"], json!(true));
    assert_eq!(ops[1]["op"], json!("subsItem"));
    assert_eq!(outcome_of(&plan, "subscriptions")["added"], json!(2));
}

#[test]
fn app_lists_are_unioned_and_counted() {
    let content = document(
        &["blocked", "excluded", "allowlist"],
        json!({
            "blocked": {"enabled": true, "packages": ["com.blocked.one"]},
            "excluded": {"packages": ["com.a"]},
            "allowlist": {"enabled": true, "rules": {"com.app": ["a.test", "b.test"]}},
        }),
    );
    let current = json!({
        "blocked": {"enabled": false, "packages": ["com.local.only"]},
        "excluded": {"packages": ["com.a", "com.b"]},
    });
    let plan = run_import(&content, current, true);
    assert_eq!(
        write_of(&plan, "blocked.packages"),
        Some(&json!(["com.blocked.one", "com.local.only"]))
    );
    // An imported enable is kept, a local one is never turned off.
    assert_eq!(write_of(&plan, "blocked.enabled"), Some(&json!(true)));
    assert_eq!(outcome_of(&plan, "blocked")["added"], json!(1));
    // `com.a` is already excluded, so only the union grows.
    assert_eq!(
        write_of(&plan, "excluded.packages"),
        Some(&json!(["com.a", "com.b"]))
    );
    assert_eq!(outcome_of(&plan, "excluded")["added"], json!(0));
    assert_eq!(outcome_of(&plan, "excluded")["skipped"], json!(1));
    assert_eq!(
        write_of(&plan, "allowlist.rules"),
        Some(&json!({"com.app": ["a.test", "b.test"]}))
    );
    assert_eq!(outcome_of(&plan, "allowlist")["added"], json!(2));
}

#[test]
fn https_inspection_imports_the_list_but_never_the_switch() {
    let content = document(
        &["httpInspection"],
        json!({"httpInspection": {"enabled": true, "http3Enabled": true, "packages": ["com.inspect.one"]}}),
    );
    let plan = run_import(
        &content,
        json!({"httpInspection": {"enabled": false, "http3Enabled": false, "packages": []}}),
        false,
    );
    assert_eq!(
        write_of(&plan, "httpInspection.packages"),
        Some(&json!(["com.inspect.one"]))
    );
    assert_eq!(write_of(&plan, "httpInspection.enabled"), None);
    assert_eq!(write_of(&plan, "httpInspection.http3"), Some(&json!(true)));
}

#[test]
fn providers_merge_by_name_and_keep_the_local_id() {
    let content = document(
        &["providers"],
        json!({"providers": {
            "itemsJson": "[{\"id\":\"user_a\",\"name\":\"我的 DoH\",\"protocol\":\"DOH\",\"url\":\"https://a.test/q\"},{\"name\":\"新增\",\"protocol\":\"DOT\",\"host\":\"b.test\"}]",
            "catalog": [],
            "selectedProviderId": "",
            "raceProviderIds": [],
        }}),
    );
    let current = json!({"providers": {
        "itemsJson": "[{\"id\":\"user_local\",\"name\":\"我的 DoH\",\"protocol\":\"DOH\",\"url\":\"https://old.test/q\"}]",
    }});
    let plan = run_import(&content, current, false);
    let outcome = outcome_of(&plan, "providers");
    assert_eq!(outcome["added"], json!(1));
    assert_eq!(outcome["updated"], json!(1));
    let items: Value = serde_json::from_str(
        write_of(&plan, "providers.items")
            .unwrap()
            .as_str()
            .unwrap(),
    )
    .unwrap();
    // The local id survives, so selections and candidate lists keep pointing at it.
    assert_eq!(items[0]["id"], json!("user_local"));
    assert_eq!(items[0]["url"], json!("https://a.test/q"));
    // A provider without an id gets one derived from its name.
    assert_eq!(items[1]["id"], json!("user___"));
    // Selection refs still travel: the empty list is written, not dropped.
    assert_eq!(write_of(&plan, "providers.race"), Some(&json!([])));
}

#[test]
fn re_importing_the_same_providers_reports_nothing_new() {
    let content = document(
        &["providers"],
        json!({"providers": {
            "itemsJson": "[{\"id\":\"user_a\",\"name\":\"我的 DoH\",\"protocol\":\"DOH\"}]",
            "catalog": [],
            "selectedProviderId": "",
        }}),
    );
    let first = run_import(&content, json!({"providers": {"itemsJson": "[]"}}), false);
    let stored = write_of(&first, "providers.items").unwrap().clone();
    let second = run_import(&content, json!({"providers": {"itemsJson": stored}}), false);
    let outcome = outcome_of(&second, "providers");
    assert_eq!(outcome["added"], json!(0));
    assert_eq!(outcome["updated"], json!(0), "重新导入不应把服务商标成更新");
    assert_eq!(outcome["skipped"], json!(1));
    assert_eq!(write_of(&second, "providers.items"), None);
}

#[test]
fn selection_resolves_by_name_when_the_id_is_gone() {
    let content = document(
        &["providers"],
        json!({"providers": {
            "itemsJson": "[]",
            "catalog": [{"id": "preset_ali", "name": "阿里", "protocol": "PLAIN"}],
            "selectedProviderId": "gone",
            "resolutionMode": "race",
            "raceTestDomain": "example.test",
            "raceProviderIds": ["preset_ali"],
            "homeVisibleProtocols": [],
        }}),
    );
    let current = json!({"providers": {
        "itemsJson": "[]",
        "presets": [{"id": "preset_ali", "name": "阿里", "protocol": "PLAIN"}],
        "homeVisibleProtocols": ["PLAIN"],
    }});
    let plan = run_import(&content, current, false);
    assert_eq!(
        write_of(&plan, "providers.race"),
        Some(&json!(["preset_ali"]))
    );
    assert_eq!(
        write_of(&plan, "providers.resolutionMode"),
        Some(&json!("race"))
    );
    assert_eq!(
        write_of(&plan, "providers.raceTestDomain"),
        Some(&json!("example.test"))
    );
    // Empty protocols keep the local filter instead of hiding everything.
    let visibility = write_of(&plan, "providers.homeVisibility").unwrap();
    assert_eq!(visibility["visibleProtocols"], json!(["PLAIN"]));
}

#[test]
fn bootstrap_round_trips_and_skips_what_it_cannot_compare() {
    let content = document(
        &["bootstrap"],
        json!({"bootstrap": {
            "enabled": true,
            "presetIds": ["ali", "dnspod"],
            "customJson": "[{\"url\":\"https://d.test/dns-query\"}]",
        }}),
    );
    let plan = run_import(
        &content,
        json!({"bootstrap": {"enabled": false, "presetIds": [], "customJson": null}}),
        false,
    );
    assert_eq!(write_of(&plan, "bootstrap.enabled"), Some(&json!(true)));
    assert_eq!(
        write_of(&plan, "bootstrap.presetIds"),
        Some(&json!(["ali", "dnspod"]))
    );
    assert_eq!(
        write_of(&plan, "bootstrap.customJson"),
        Some(&json!("[{\"url\":\"https://d.test/dns-query\"}]"))
    );
    assert_eq!(outcome_of(&plan, "bootstrap")["added"], json!(3));

    // Same file, same device: every key is already in place.
    let current = json!({"bootstrap": {
        "enabled": true,
        "presetIds": ["ali", "dnspod"],
        "customJson": "[{\"url\":\"https://d.test/dns-query\"}]",
    }});
    let again = run_import(&content, current, false);
    assert_eq!(again["writes"], json!([]));
    assert_eq!(outcome_of(&again, "bootstrap")["skipped"], json!(3));
}

#[test]
fn cache_is_written_as_one_policy() {
    let content = document(
        &["cache"],
        json!({"cache": {
            "enabled": true, "mode": "fixed", "maxTtlSeconds": 86400,
            "fixedTtlSeconds": 600, "minTtlEnabled": true, "minTtlSeconds": 30,
            "staleFallbackEnabled": true, "staleFallbackSeconds": 900,
            "preset": "custom",
        }}),
    );
    let current = json!({"cache": {
        "enabled": false, "mode": "auto", "maxTtlSeconds": 3600,
        "fixedTtlSeconds": 300, "minTtlEnabled": false, "minTtlSeconds": 10,
        "staleFallbackEnabled": false, "staleFallbackSeconds": 600, "preset": "balanced",
    }});
    let plan = run_import(&content, current, false);
    let config = write_of(&plan, "cache.config").expect("cache policy");
    assert_eq!(config["fixedTtlSeconds"], json!(600));
    assert_eq!(config["preset"], json!("custom"));
    // Nine keys, one policy: counting them separately would look like nine rules.
    assert_eq!(outcome_of(&plan, "cache")["added"], json!(1));

    let again = run_import(
        &content,
        json!({"cache": {
            "enabled": true, "mode": "fixed", "maxTtlSeconds": 86400,
            "fixedTtlSeconds": 600, "minTtlEnabled": true, "minTtlSeconds": 30,
            "staleFallbackEnabled": true, "staleFallbackSeconds": 900,
            "preset": "custom",
        }}),
        false,
    );
    assert_eq!(again["writes"], json!([]));
    assert_eq!(outcome_of(&again, "cache")["skipped"], json!(1));
}

#[test]
fn outbound_never_touches_credentials_or_the_switch() {
    let content = document(
        &["outbound"],
        json!({"outbound": {
            "enabled": true, "protocol": "socks5", "host": "h.test", "port": 1080,
            "proxyAppPackage": "com.target",
        }}),
    );
    let plan = run_import(
        &content,
        json!({"outbound": {"protocol": "http", "host": null, "port": null}}),
        false,
    );
    assert_eq!(write_of(&plan, "outbound.protocol"), Some(&json!("socks5")));
    assert_eq!(write_of(&plan, "outbound.host"), Some(&json!("h.test")));
    assert_eq!(write_of(&plan, "outbound.port"), Some(&json!(1080)));
    assert_eq!(write_of(&plan, "outbound.app"), Some(&json!("com.target")));
    assert_eq!(write_of(&plan, "outbound.enabled"), None);
    assert_eq!(outcome_of(&plan, "outbound")["added"], json!(4));
    // The proxy switch and the credentials are never restored, so nothing else is counted.
    assert_eq!(outcome_of(&plan, "outbound")["skipped"], json!(0));
}

#[test]
fn appearance_keeps_local_theme_and_rounds_opacity() {
    let content = document(
        &["appearance"],
        json!({"appearance": {
            "themeMode": "dark",
            "palette": "blue",
            "componentOpacity": 0.800000011920929,
            "hapticEnabled": true,
            "bottomBarIds": ["home", "settings"],
        }}),
    );
    let current = json!({"appearance": {
        "themeMode": "light",
        "palette": "",
        "componentOpacity": 0.800000011920929,
        "hapticEnabled": false,
        "bottomBarIds": ["home", "settings"],
    }});
    let plan = run_import(&content, current, false);
    // A device that already picked a theme keeps it; an empty palette accepts the file's.
    assert_eq!(write_of(&plan, "appearance.themeMode"), None);
    assert_eq!(write_of(&plan, "appearance.palette"), Some(&json!("blue")));
    // Java `float` opacity compares with a tolerance, so 0.8 is not a change.
    let home = plan["writes"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|write| write["field"] == json!("appearance.homeOpacity"))
        .count();
    assert_eq!(home, 0);
    assert_eq!(write_of(&plan, "appearance.componentOpacity"), None);
    assert_eq!(
        write_of(&plan, "appearance.hapticEnabled"),
        Some(&json!(true))
    );
    let outcome = outcome_of(&plan, "appearance");
    assert_eq!(outcome["added"], json!(2));
    // Theme, bottom bar, five sliders and the shared one already match.
    assert_eq!(outcome["skipped"], json!(8));
}

#[test]
fn appearance_rejects_an_unusable_bottom_bar() {
    let content = document(
        &["appearance"],
        json!({"appearance": {"bottomBarIds": ["home"]}}),
    );
    let plan = run_import(
        &content,
        json!({"appearance": {"bottomBarIds": ["home", "settings"]}}),
        false,
    );
    assert_eq!(write_of(&plan, "appearance.bottomBarIds"), None);
    // An unusable bar is skipped, and so is every default the file carries.
    assert_eq!(outcome_of(&plan, "appearance")["skipped"], json!(8));
}

#[test]
fn system_clamps_the_dynamic_block_policy_and_keeps_raw_defaults() {
    let content = document(
        &["system"],
        json!({"system": {
            "bypassLan": true,
            "appTrafficStatsEnabled": false,
            "trafficStatsRetentionDays": 90,
            "allowEditDefaultWhitelist": false,
            "dynamicBlockResponse": {
                "enabled": true, "requestThreshold": 1000,
                "windowSeconds": 1, "nxDomainDurationSeconds": 99999,
            },
        }}),
    );
    let plan = run_import(&content, json!({"system": {"bypassLan": false}}), false);
    assert_eq!(write_of(&plan, "system.bypassLan"), Some(&json!(true)));
    let policy = write_of(&plan, "system.dynamicBlockPolicy").expect("policy");
    assert_eq!(policy["requestThreshold"], json!(100));
    assert_eq!(policy["windowSeconds"], json!(10));
    assert_eq!(policy["nxDomainDurationSeconds"], json!(3600));
    // Raw prefs are compared as stored, so an unset local value accepts the file's.
    assert_eq!(
        write_of(&plan, "system.trafficStats"),
        Some(&json!({"key": "app_traffic_stats_enabled", "value": false}))
    );
}

#[test]
fn a_system_group_with_nothing_to_say_still_reports_one_skip() {
    // A hand-written group with no keys at all: nothing to compare, nothing to write.
    let content = "{\"format\":\"diting-backup\",\"version\":2,\"data\":{\"system\":{}}}";
    let content: String = content.to_string();
    let plan = run_import(&content, json!({"system": {}}), false);
    assert_eq!(plan["writes"], json!([]));
    assert_eq!(outcome_of(&plan, "system")["added"], json!(0));
    assert_eq!(outcome_of(&plan, "system")["skipped"], json!(1));
}

#[test]
fn corrupt_group_snapshots_are_reported_at_export_time() {
    let output = export::run(&json!({
        "nowMs": 1,
        "groups": ["providers", "excluded"],
        "fields": {
            "providers": {"itemsJson": "{"},
            "excluded": {"packages": ["com.a"]},
        },
    }));
    assert_eq!(
        output["skipped"],
        json!([{"group": "providers", "reason": "providersInvalidJson"}])
    );
    assert_eq!(output["included"], json!(["excluded"]));
    // The group is simply absent from the file, so an import does not report it either.
    let content = output["content"].as_str().unwrap();
    let plan = run_import(content, json!({}), false);
    assert_eq!(plan["outcomes"].as_array().unwrap().len(), 1);
}
