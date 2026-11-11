//! One builder per group: snapshot in, document value out.
//!
//! Snapshot fields are read with the same fallbacks the app used (`enabled` as an int or a bool,
//! `null` for "not set"), so a group never fails for a reason the app would not have failed on.

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use crate::groups::Group;
use crate::value::{array, as_object, boolean, get, integer, round_opacity, sorted_strings, text};

type Catalog = BTreeMap<String, (String, String)>;

pub(super) fn build(group: Group, source: &Value) -> Result<Value, &'static str> {
    Ok(match group {
        Group::Providers => providers(source)?,
        Group::Bootstrap => bootstrap(source)?,
        Group::Cache => cache(source),
        Group::Outbound => outbound(source),
        Group::Subscriptions => subscriptions(source),
        Group::DomainRules => domain_rules(source),
        Group::RewriteDomain | Group::RewriteCname => rewrite(group, source),
        Group::AddressRules => address_rules(source),
        Group::Excluded => Value::Array(sorted_strings(
            &get(source, "packages").cloned().unwrap_or(Value::Null),
        )),
        Group::Blocked => json!({
            "enabled": boolean(source, "enabled").unwrap_or(false),
            "packages": sorted_strings(&get(source, "packages").cloned().unwrap_or(Value::Null)),
        }),
        Group::Allowlist => allowlist(source),
        Group::HttpInspection => json!({
            "enabled": boolean(source, "enabled").unwrap_or(false),
            "http3Enabled": boolean(source, "http3Enabled").unwrap_or(false),
            "packages": sorted_strings(&get(source, "packages").cloned().unwrap_or(Value::Null)),
        }),
        Group::Appearance => appearance(source),
        Group::System => system(source),
    })
}

/// `enabled` / `important` / `appInverted`: stored as ints, written as bools.
fn flag(value: &Value, key: &str, default: bool) -> bool {
    match get(value, key) {
        Some(Value::Bool(flag)) => *flag,
        Some(Value::Number(number)) => number.as_i64().map(|flag| flag != 0).unwrap_or(default),
        _ => default,
    }
}

fn providers(source: &Value) -> Result<Value, &'static str> {
    let raw = get(source, "itemsJson")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let items = if raw.trim().is_empty() {
        Value::Array(Vec::new())
    } else {
        // Corrupt local JSON is reported: a restore must not look like it lost the providers.
        let decoded: Value = serde_json::from_str(raw).map_err(|_| "providersInvalidJson")?;
        match decoded {
            Value::Array(_) => decoded,
            _ => Value::Array(Vec::new()),
        }
    };
    Ok(json!({"items": items, "selection": selection(source)}))
}

fn provider_catalog(source: &Value) -> Catalog {
    let mut catalog = Catalog::new();
    for entry in array(source, "catalog") {
        let Some(id) = text(&entry, "id") else {
            continue;
        };
        let name = text(&entry, "name").unwrap_or_else(|| id.clone());
        let protocol = text(&entry, "protocol").unwrap_or_else(|| String::from("DOH"));
        catalog.insert(id, (name, protocol));
    }
    catalog
}

/// A provider reference carries `name` and `protocol` so it resolves on another device, where ids
/// of user providers are regenerated.
fn provider_ref(catalog: &Catalog, id: &str) -> Value {
    let (name, protocol) = match catalog.get(id) {
        Some((name, protocol)) => (name.clone(), protocol.clone()),
        None => (String::from(id), String::from("DOH")),
    };
    json!({
        "id": id,
        "name": name,
        "protocol": protocol,
        "isPreset": id.starts_with("preset_"),
    })
}

fn provider_refs(catalog: &Catalog, source: &Value, key: &str) -> Vec<Value> {
    array(source, key)
        .iter()
        .filter_map(Value::as_str)
        .map(|id| provider_ref(catalog, id))
        .collect()
}

fn selection(source: &Value) -> Value {
    let catalog = provider_catalog(source);
    let selected = text(source, "selectedProviderId").unwrap_or_default();
    json!({
        "selectedProvider": provider_ref(&catalog, &selected),
        "resolutionMode": text(source, "resolutionMode"),
        "presetDnsService": text(source, "presetDnsService"),
        "raceTestDomain": text(source, "raceTestDomain"),
        "raceProviderRefs": provider_refs(&catalog, source, "raceProviderIds"),
        "smartPredictionProviderRefs":
            provider_refs(&catalog, source, "smartPredictionProviderIds"),
        "parallelRaceProviderRefs": provider_refs(&catalog, source, "parallelRaceProviderIds"),
        "primaryBackupProviderRefs": provider_refs(&catalog, source, "primaryBackupProviderIds"),
        "latencyTestProviderRefs": provider_refs(&catalog, source, "latencyTestProviderIds"),
        "homeProviderVisibility": {
            "visibleProtocols":
                sorted_strings(&get(source, "homeVisibleProtocols").cloned().unwrap_or(Value::Null)),
            "hiddenProviderRefs": provider_refs(&catalog, source, "homeHiddenProviderIds"),
            "visibleProviderRefs": provider_refs(&catalog, source, "homeVisibleProviderIds"),
        },
    })
}

fn bootstrap(source: &Value) -> Result<Value, &'static str> {
    let custom = get(source, "customJson")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let parsed = if custom.trim().is_empty() {
        Value::Null
    } else {
        serde_json::from_str(custom).map_err(|_| "bootstrapInvalidJson")?
    };
    Ok(json!({
        "enabled": boolean(source, "enabled").unwrap_or(false),
        "presetIds": array(source, "presetIds"),
        "custom": parsed,
    }))
}

fn cache(source: &Value) -> Value {
    json!({
        "enabled": boolean(source, "enabled").unwrap_or(false),
        "mode": text(source, "mode"),
        "maxTtlSeconds": integer(source, "maxTtlSeconds"),
        "fixedTtlSeconds": integer(source, "fixedTtlSeconds"),
        "minTtlEnabled": boolean(source, "minTtlEnabled").unwrap_or(false),
        "minTtlSeconds": integer(source, "minTtlSeconds"),
        "staleFallbackEnabled": boolean(source, "staleFallbackEnabled").unwrap_or(false),
        "staleFallbackSeconds": integer(source, "staleFallbackSeconds"),
        "preset": text(source, "preset"),
    })
}

/// Protocol, host, port and target app only; credentials are excluded and the file says so.
fn outbound(source: &Value) -> Value {
    json!({
        "enabled": boolean(source, "enabled").unwrap_or(false),
        "protocol": text(source, "protocol"),
        "host": text(source, "host"),
        "port": get(source, "port").cloned().unwrap_or(Value::Null),
        "proxyAppPackage": text(source, "proxyAppPackage"),
        "credentialsExcluded": true,
    })
}

fn group_name_of(groups: &[Value], group_id: Option<i64>) -> Option<String> {
    let wanted = group_id?;
    groups
        .iter()
        .find(|group| integer(group, "id") == Some(wanted))
        .and_then(|group| text(group, "name"))
}

pub fn normalize_kind(value: Option<&Value>) -> &'static str {
    match value.and_then(Value::as_str) {
        Some(text) if text.trim().to_lowercase() == "hosts" => "hosts",
        _ => "domain",
    }
}

pub fn normalize_source(value: Option<&Value>) -> &'static str {
    match value.and_then(Value::as_str) {
        Some("local") => "local",
        _ => "remote",
    }
}

fn subscriptions(source: &Value) -> Value {
    let groups = array(source, "groups");
    let items: Vec<Value> = array(source, "items")
        .into_iter()
        .map(|row| {
            json!({
                "url": text(&row, "url"),
                "name": text(&row, "name"),
                "kind": normalize_kind(get(&row, "kind")),
                "scope": "dns",
                "sourceType": normalize_source(get(&row, "sourceType")),
                "enabled": flag(&row, "enabled", true),
                "groupName": group_name_of(&groups, integer(&row, "groupId")),
                "mirrorTemplate": text(&row, "mirrorTemplate"),
                "mirrorFallback": flag(&row, "mirrorFallback", true),
            })
        })
        .collect();
    let templates: Vec<Value> = array(source, "mirrorTemplates")
        .into_iter()
        .map(|row| {
            json!({
                "name": text(&row, "name"),
                "template": text(&row, "template"),
            })
        })
        .collect();
    json!({"groups": groups, "mirrorTemplates": templates, "items": items})
}

fn domain_rules(source: &Value) -> Value {
    let mut exported = Vec::new();
    for (key, kind) in [("block", "block"), ("allow", "allow")] {
        for row in array(source, key) {
            exported.push(json!({
                "pattern": text(&row, "pattern"),
                "kind": kind,
                "enabled": flag(&row, "enabled", true),
                "important": flag(&row, "important", false),
                "appScope": text(&row, "appScope"),
                "appInverted": flag(&row, "appInverted", false),
                "rawLine": text(&row, "rawLine"),
                "group": text(&row, "groupName"),
            }));
        }
    }
    Value::Array(exported)
}

fn rewrite(group: Group, source: &Value) -> Value {
    let target_types = group.target_types();
    let rows: Vec<Value> = array(source, "rows")
        .into_iter()
        .filter(|row| {
            text(row, "targetType")
                .map(|kind| target_types.contains(&kind.as_str()))
                .unwrap_or(false)
        })
        .map(|row| {
            json!({
                "pattern": text(&row, "pattern"),
                "targetType": text(&row, "targetType"),
                "targetValue": text(&row, "targetValue"),
                "rawLine": text(&row, "rawLine"),
                "enabled": flag(&row, "enabled", true),
            })
        })
        .collect();
    Value::Array(rows)
}

fn address_rules(source: &Value) -> Value {
    Value::Array(
        array(source, "rows")
            .into_iter()
            .map(|row| {
                json!({
                    "pattern": text(&row, "pattern"),
                    "kind": text(&row, "kind"),
                    "rawLine": text(&row, "rawLine"),
                    "enabled": flag(&row, "enabled", true),
                })
            })
            .collect(),
    )
}

/// Per-app domains: `{package: [domain]}` with sorted domains.
fn allowlist(source: &Value) -> Value {
    let mut rules = Map::new();
    if let Some(record) = get(source, "rules").and_then(as_object) {
        for (package, domains) in record {
            rules.insert(package.clone(), Value::Array(sorted_strings(domains)));
        }
    }
    json!({
        "enabled": boolean(source, "enabled").unwrap_or(false),
        "rules": Value::Object(rules),
    })
}

fn appearance(source: &Value) -> Value {
    // One opacity slider now; the per-widget keys fall back to it, so a device that only ever moved
    // the shared slider still exports five consistent values.
    let component = get(source, "componentOpacity").and_then(Value::as_f64);
    let opacity = |key: &str| {
        get(source, key)
            .and_then(Value::as_f64)
            .or(component)
            .map(round_opacity)
            .unwrap_or_else(|| json!(1.0))
    };
    json!({
        "themeMode": text(source, "themeMode"),
        "palette": text(source, "palette"),
        "liquidGlassMode": text(source, "liquidGlassMode"),
        "bottomBarStyle": text(source, "bottomBarStyle"),
        "tabTransition": text(source, "tabTransition"),
        "componentOpacity": opacity("componentOpacity"),
        "hapticEnabled": boolean(source, "hapticEnabled").unwrap_or(false),
        "bottomBarIds": array(source, "bottomBarIds"),
        "customBackgroundEnabled": boolean(source, "customBackgroundEnabled").unwrap_or(false),
        // One opacity slider now; the per-widget keys are still written for older builds.
        "homePowerButtonOpacity": opacity("homePowerButtonOpacity"),
        "homeProviderSelectorOpacity": opacity("homeProviderSelectorOpacity"),
        "homeModeButtonOpacity": opacity("homeModeButtonOpacity"),
        "homePoemOpacity": opacity("homePoemOpacity"),
        "homeDnsDetailOpacity": opacity("homeDnsDetailOpacity"),
        "homeSentenceRunning": text(source, "homeSentenceRunning"),
        "homeSentenceStopped": text(source, "homeSentenceStopped"),
        "customBackgroundUri": text(source, "customBackgroundUri"),
    })
}

fn system(source: &Value) -> Value {
    let dynamic = get(source, "dynamicBlockResponse")
        .cloned()
        .unwrap_or(Value::Null);
    let dynamic_flag = flag(&dynamic, "enabled", false);
    json!({
        "bypassLan": boolean(source, "bypassLan").unwrap_or(false),
        "ipv6Mode": text(source, "ipv6Mode"),
        "logRetentionDays": integer(source, "logRetentionDays"),
        "dnsLogMode": text(source, "dnsLogMode"),
        "hideFromRecents": boolean(source, "hideFromRecents").unwrap_or(false),
        "floatingLogEnabled": boolean(source, "floatingLogEnabled").unwrap_or(false),
        "floatingLogPanelSize": get(source, "floatingLogPanelSize").cloned().unwrap_or(Value::Null),
        "disableStartupUpdateCheck": boolean(source, "disableStartupUpdateCheck").unwrap_or(false),
        "appLanguageMode": text(source, "appLanguageMode"),
        "notificationPersistent": boolean(source, "notificationPersistent").unwrap_or(false),
        "notificationSpeed": boolean(source, "notificationSpeed").unwrap_or(false),
        "notificationStatsItems": array(source, "notificationStatsItems"),
        "customRunningNotificationText": text(source, "customRunningNotificationText"),
        "customStoppedNotificationText": text(source, "customStoppedNotificationText"),
        "domainRulesEnabled": boolean(source, "domainRulesEnabled").unwrap_or(false),
        "addressRulesEnabled": boolean(source, "addressRulesEnabled").unwrap_or(false),
        "encryptedDnsBlockingEnabled": boolean(source, "encryptedDnsBlockingEnabled").unwrap_or(false),
        "blockResponseMode": text(source, "blockResponseMode"),
        "allowEditDefaultWhitelist": boolean(source, "allowEditDefaultWhitelist").unwrap_or(false),
        "dynamicBlockResponse": {
            "enabled": dynamic_flag,
            "requestThreshold": integer(&dynamic, "requestThreshold"),
            "windowSeconds": integer(&dynamic, "windowSeconds"),
            "nxDomainDurationSeconds": integer(&dynamic, "nxDomainDurationSeconds"),
        },
        "appTrafficStatsEnabled": boolean(source, "appTrafficStatsEnabled").unwrap_or(true),
        "trafficStatsRetentionDays": integer(source, "trafficStatsRetentionDays").unwrap_or(30),
        "trafficStatsHideSystemApps": boolean(source, "trafficStatsHideSystemApps").unwrap_or(false),
        "subscriptionAutoUpdateEnabled": boolean(source, "subscriptionAutoUpdateEnabled").unwrap_or(false),
        "subscriptionAutoUpdateIntervalHours":
            integer(source, "subscriptionAutoUpdateIntervalHours"),
        "subscriptionAutoUpdateSchedule": text(source, "subscriptionAutoUpdateSchedule"),
        "subscriptionAutoUpdateTimeMinutes": integer(source, "subscriptionAutoUpdateTimeMinutes"),
    })
}

#[cfg(test)]
#[path = "values/tests.rs"]
mod tests;
