//! Appearance and system groups; local values win where a key is already set.
//!
//! Only fields the app can act on are merged: the background image and its switch stay local, since
//! a file path from another device points at nothing here.

use serde_json::{json, Value};

use super::{same_order, strings, Outcome, Plan};
use crate::groups::Group;
use crate::value::{boolean, decimal, get, integer, number, text};

/// Below this many tabs the bottom bar cannot be laid out, so the local list is kept.
const BOTTOM_BAR_MIN: usize = 2;

/// Android stores opacity as a Java `float`; `putFloat(0.8)` reads back as `0.800000011920929`.
const OPACITY_TOLERANCE: f64 = 0.001;

fn apply_text(
    outcome: &mut Outcome,
    plan: &mut Plan,
    field: &str,
    value: &Value,
    key: &str,
    current: &Value,
) {
    let Some(incoming) = text(value, key) else {
        return;
    };
    if text(current, key).as_deref() == Some(incoming.as_str()) {
        outcome.skipped += 1;
    } else {
        plan.write(field, Value::String(incoming));
        outcome.added += 1;
    }
}

fn apply_bool(
    outcome: &mut Outcome,
    plan: &mut Plan,
    field: &str,
    value: &Value,
    key: &str,
    current: &Value,
) {
    let Some(incoming) = boolean(value, key) else {
        return;
    };
    if boolean(current, key).unwrap_or(false) == incoming {
        outcome.skipped += 1;
    } else {
        plan.write(field, json!(incoming));
        outcome.added += 1;
    }
}

fn apply_int(
    outcome: &mut Outcome,
    plan: &mut Plan,
    field: &str,
    value: &Value,
    key: &str,
    current: &Value,
) {
    let Some(incoming) = integer(value, key) else {
        return;
    };
    if integer(current, key) == Some(incoming) {
        outcome.skipped += 1;
    } else {
        plan.write(field, json!(incoming));
        outcome.added += 1;
    }
}

/// A value the app stores raw (`bool` or `int`), compared against the raw local value so an
/// unchanged key does not report an update.
fn apply_raw(
    outcome: &mut Outcome,
    plan: &mut Plan,
    value: &Value,
    key: &str,
    stored: &str,
    current: &Value,
) {
    let Some(incoming) = get(value, key) else {
        return;
    };
    if !incoming.is_boolean() && !incoming.is_number() {
        return;
    }
    // Raw prefs are compared as stored: an unset key accepts the file's value.
    if get(current, stored) == Some(incoming) {
        outcome.skipped += 1;
        return;
    }
    plan.write(
        "system.trafficStats",
        json!({"key": stored, "value": incoming}),
    );
    outcome.added += 1;
}

pub fn appearance(
    value: &Value,
    current: &Value,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    if !value.is_object() {
        return Err("appearanceNotObject");
    }
    let mut outcome = Outcome::new(Group::Appearance);

    // Theme and palette: a device that already picked one keeps it.
    for (key, field) in [
        ("themeMode", "appearance.themeMode"),
        ("palette", "appearance.palette"),
    ] {
        let Some(incoming) = text(value, key) else {
            continue;
        };
        let local = text(current, key).unwrap_or_default();
        if !local.is_empty() {
            outcome.skipped += 1;
        } else {
            plan.write(field, Value::String(incoming));
            outcome.added += 1;
        }
    }

    if let Some(Value::Array(_)) = get(value, "bottomBarIds") {
        let ids = strings(get(value, "bottomBarIds").unwrap_or(&Value::Null));
        let local = strings(get(current, "bottomBarIds").unwrap_or(&Value::Null));
        if ids.len() < BOTTOM_BAR_MIN || same_order(&ids, &local) {
            outcome.skipped += 1;
        } else {
            plan.write("appearance.bottomBarIds", json!(ids));
            outcome.added += 1;
        }
    }

    // The glass mode is device capability, so an incoming value replaces the local one.
    apply_text(
        &mut outcome,
        plan,
        "appearance.liquidGlassMode",
        value,
        "liquidGlassMode",
        current,
    );
    apply_bool(
        &mut outcome,
        plan,
        "appearance.hapticEnabled",
        value,
        "hapticEnabled",
        current,
    );

    // This build has one shared `componentOpacity`; old backups held five separate keys, so each
    // present value is written back to its legacy key.
    let component = decimal(value, "componentOpacity");
    for key in [
        "homePowerButtonOpacity",
        "homeProviderSelectorOpacity",
        "homeModeButtonOpacity",
        "homePoemOpacity",
        "homeDnsDetailOpacity",
    ] {
        let Some(opacity) = decimal(value, key).or(component) else {
            continue;
        };
        let local = number(current, key)
            .or(number(current, "componentOpacity"))
            .unwrap_or(1.0);
        if (local - opacity).abs() < OPACITY_TOLERANCE {
            outcome.skipped += 1;
        } else {
            plan.write(
                "appearance.homeOpacity",
                json!({"key": key, "value": opacity}),
            );
            outcome.added += 1;
        }
    }
    if let Some(component) = component {
        let local = number(current, "componentOpacity").unwrap_or(1.0);
        if (local - component).abs() < OPACITY_TOLERANCE {
            outcome.skipped += 1;
        } else {
            plan.write("appearance.componentOpacity", json!(component));
            outcome.added += 1;
        }
    }

    let running = get(value, "homeSentenceRunning").and_then(Value::as_str);
    let stopped = get(value, "homeSentenceStopped").and_then(Value::as_str);
    if running.is_some() || stopped.is_some() {
        let next_running = running
            .filter(|text| !text.is_empty())
            .map(str::to_string)
            .or_else(|| text(current, "homeSentenceRunning"))
            .unwrap_or_default();
        let next_stopped = stopped
            .filter(|text| !text.is_empty())
            .map(str::to_string)
            .or_else(|| text(current, "homeSentenceStopped"))
            .unwrap_or_default();
        if next_running == text(current, "homeSentenceRunning").unwrap_or_default()
            && next_stopped == text(current, "homeSentenceStopped").unwrap_or_default()
        {
            outcome.skipped += 1;
        } else {
            plan.write(
                "appearance.homeSentences",
                json!({"running": next_running, "stopped": next_stopped}),
            );
            outcome.added += 1;
        }
    }

    Ok(outcome)
}

pub fn system(
    value: &Value,
    current: &Value,
    _now: i64,
    plan: &mut Plan,
) -> Result<Outcome, &'static str> {
    if !value.is_object() {
        return Err("systemNotObject");
    }
    let mut outcome = Outcome::new(Group::System);

    for (key, field) in [
        ("bypassLan", "system.bypassLan"),
        ("hideFromRecents", "system.hideFromRecents"),
        ("floatingLogEnabled", "system.floatingLogEnabled"),
        (
            "disableStartupUpdateCheck",
            "system.disableStartupUpdateCheck",
        ),
        ("notificationPersistent", "system.notificationPersistent"),
        ("notificationSpeed", "system.notificationSpeed"),
        ("domainRulesEnabled", "system.domainRulesEnabled"),
    ] {
        apply_bool(&mut outcome, plan, field, value, key, current);
    }
    for (key, field) in [
        ("ipv6Mode", "system.ipv6Mode"),
        ("dnsLogMode", "system.dnsLogMode"),
        ("appLanguageMode", "system.appLanguageMode"),
        ("blockResponseMode", "system.blockResponseMode"),
    ] {
        apply_text(&mut outcome, plan, field, value, key, current);
    }
    apply_int(
        &mut outcome,
        plan,
        "system.logRetentionDays",
        value,
        "logRetentionDays",
        current,
    );
    // The panel size is stored raw, so a device that never touched it accepts the file's value.
    if let Some(size) = integer(value, "floatingLogPanelSize") {
        if integer(current, "floating_log_panel_size") == Some(size) {
            outcome.skipped += 1;
        } else {
            plan.write("system.floatingLogPanelSize", json!(size));
            outcome.added += 1;
        }
    }

    // After the speed switch: the list is the newer, more precise value and also sets it.
    if let Some(Value::Array(_)) = get(value, "notificationStatsItems") {
        let ids = strings(get(value, "notificationStatsItems").unwrap_or(&Value::Null));
        if same_order(
            &ids,
            &strings(get(current, "notificationStatsItems").unwrap_or(&Value::Null)),
        ) {
            outcome.skipped += 1;
        } else {
            plan.write("system.notificationStatsItems", json!(ids));
            outcome.added += 1;
        }
    }

    let running = get(value, "customRunningNotificationText").and_then(Value::as_str);
    let stopped = get(value, "customStoppedNotificationText").and_then(Value::as_str);
    if running.is_some() || stopped.is_some() {
        let next_running = running
            .map(str::to_string)
            .or_else(|| text(current, "customRunningNotificationText"))
            .unwrap_or_default();
        let next_stopped = stopped
            .map(str::to_string)
            .or_else(|| text(current, "customStoppedNotificationText"))
            .unwrap_or_default();
        if next_running == text(current, "customRunningNotificationText").unwrap_or_default()
            && next_stopped == text(current, "customStoppedNotificationText").unwrap_or_default()
        {
            outcome.skipped += 1;
        } else {
            plan.write(
                "system.notificationTexts",
                json!({"running": next_running, "stopped": next_stopped}),
            );
            outcome.added += 1;
        }
    }

    // Address rules, encrypted-DNS blocking and HTTP/3 share one entry point; each keeps its local
    // value when the file does not carry it.
    let address_rules = boolean(value, "addressRulesEnabled");
    let encrypted_dns = boolean(value, "encryptedDnsBlockingEnabled");
    let http3 = boolean(value, "http3Enabled");
    if address_rules.is_some() || encrypted_dns.is_some() || http3.is_some() {
        let next_address = address_rules
            .unwrap_or_else(|| boolean(current, "addressRulesEnabled").unwrap_or(false));
        let next_encrypted = encrypted_dns
            .unwrap_or_else(|| boolean(current, "encryptedDnsBlockingEnabled").unwrap_or(false));
        let next_http3 = http3.unwrap_or_else(|| boolean(current, "http3Enabled").unwrap_or(false));
        if next_address == boolean(current, "addressRulesEnabled").unwrap_or(false)
            && next_encrypted == boolean(current, "encryptedDnsBlockingEnabled").unwrap_or(false)
            && next_http3 == boolean(current, "http3Enabled").unwrap_or(false)
        {
            outcome.skipped += 1;
        } else {
            plan.write(
                "system.httpInspectionToggles",
                json!({
                    "http3": next_http3,
                    "encryptedDns": next_encrypted,
                    "addressRules": next_address,
                }),
            );
            outcome.added += 1;
        }
    }

    if let Some(allow) = boolean(value, "allowEditDefaultWhitelist") {
        if get(current, "allow_edit_default_whitelist") == Some(&Value::Bool(allow)) {
            outcome.skipped += 1;
        } else {
            plan.write("system.allowEditDefaultWhitelist", json!(allow));
            outcome.added += 1;
        }
    }

    if let Some(policy) = get(value, "dynamicBlockResponse").filter(|value| value.is_object()) {
        let local = get(current, "dynamicBlockResponse")
            .cloned()
            .unwrap_or(Value::Null);
        let enabled = boolean(policy, "enabled")
            .unwrap_or_else(|| boolean(&local, "enabled").unwrap_or(false));
        let threshold = clamp_field(policy, &local, "requestThreshold", 2, 100);
        let window = clamp_field(policy, &local, "windowSeconds", 10, 300);
        let duration = clamp_field(policy, &local, "nxDomainDurationSeconds", 60, 3600);
        if enabled == boolean(&local, "enabled").unwrap_or(false)
            && threshold == integer(&local, "requestThreshold").unwrap_or(threshold)
            && window == integer(&local, "windowSeconds").unwrap_or(window)
            && duration == integer(&local, "nxDomainDurationSeconds").unwrap_or(duration)
        {
            outcome.skipped += 1;
        } else {
            plan.write(
                "system.dynamicBlockPolicy",
                json!({
                    "enabled": enabled,
                    "requestThreshold": threshold,
                    "windowSeconds": window,
                    "nxDomainDurationSeconds": duration,
                }),
            );
            outcome.added += 1;
        }
    }

    for (key, stored) in [
        ("appTrafficStatsEnabled", "app_traffic_stats_enabled"),
        ("trafficStatsRetentionDays", "traffic_stats_retention_days"),
        (
            "trafficStatsHideSystemApps",
            "traffic_stats_hide_system_apps",
        ),
    ] {
        apply_raw(&mut outcome, plan, value, key, stored, current);
    }

    apply_bool(
        &mut outcome,
        plan,
        "system.subscriptionAutoUpdateEnabled",
        value,
        "subscriptionAutoUpdateEnabled",
        current,
    );
    apply_int(
        &mut outcome,
        plan,
        "system.subscriptionAutoUpdateIntervalHours",
        value,
        "subscriptionAutoUpdateIntervalHours",
        current,
    );

    let schedule = text(value, "subscriptionAutoUpdateSchedule");
    let time_minutes = integer(value, "subscriptionAutoUpdateTimeMinutes");
    if schedule.is_some() || time_minutes.is_some() {
        let next_schedule = schedule
            .or_else(|| text(current, "subscriptionAutoUpdateSchedule"))
            .unwrap_or_default();
        let next_time = time_minutes
            .or_else(|| integer(current, "subscriptionAutoUpdateTimeMinutes"))
            .unwrap_or_default();
        if next_schedule == text(current, "subscriptionAutoUpdateSchedule").unwrap_or_default()
            && next_time
                == integer(current, "subscriptionAutoUpdateTimeMinutes").unwrap_or_default()
        {
            outcome.skipped += 1;
        } else {
            plan.write(
                "system.subscriptionAutoUpdateSchedule",
                json!({"schedule": next_schedule, "timeMinutes": next_time}),
            );
            outcome.added += 1;
        }
    }

    if outcome.skipped == 0 && outcome.added == 0 {
        outcome.skipped = 1;
    }
    Ok(outcome)
}

/// Clamped policy values; a missing or non-numeric field keeps the local value.
fn clamp_field(policy: &Value, local: &Value, key: &str, min: i64, max: i64) -> i64 {
    number(policy, key)
        .map(|value| (value.trunc() as i64).clamp(min, max))
        .unwrap_or_else(|| integer(local, key).unwrap_or(min))
}
