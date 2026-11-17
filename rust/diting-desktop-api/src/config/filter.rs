//! Rule filtering, subscription lists and blocking schedules.

use std::collections::HashMap;

use serde::{Deserialize, Deserializer, Serialize};

use super::paths::default_filter_dir;
use super::serde_util::{nullable_map, nullable_vec};

/// Return an empty IP address for blocked names.
pub const BLOCK_MODE_NULL_IP: &str = "null_ip";
/// Return NXDOMAIN for blocked names.
pub const BLOCK_MODE_NXDOMAIN: &str = "nxdomain";
/// Return REFUSED for blocked names.
pub const BLOCK_MODE_REFUSED: &str = "refused";
/// Default IPv4 blocking address.
pub const DEFAULT_BLOCKING_IPV4: &str = "0.0.0.0";
/// Default IPv6 blocking address.
pub const DEFAULT_BLOCKING_IPV6: &str = "::";
/// Default interval between subscription refreshes.
const DEFAULT_UPDATE_INTERVAL_HOURS: i32 = 24;

const WEEKDAY_KEYS: [&str; 7] = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

/// A weekly blocking window.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct BlockingSchedule {
    pub id: String,
    pub name: String,
    pub enabled: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub weekdays: Vec<String>,
    pub start: String,
    pub end: String,
}

impl BlockingSchedule {
    /// Validate the window and fill in a generated id/name. Invalid entries are dropped by the
    /// caller, matching Go's "bad config must not disable blocking entirely" behaviour.
    pub fn normalize(&mut self) -> Result<(), String> {
        self.id = self.id.trim().to_string();
        if self.id.is_empty() {
            self.id = format!("schedule-{}", super::timestamp_nanos());
        }
        self.name = self.name.trim().to_string();
        if self.name.is_empty() {
            self.name = self.id.clone();
        }
        parse_schedule_clock(&self.start)?;
        parse_schedule_clock(&self.end)?;
        parse_schedule_weekdays(&self.weekdays)?;
        Ok(())
    }
}

fn parse_schedule_clock(raw: &str) -> Result<i32, String> {
    let value = raw.trim();
    if value.is_empty() {
        return Err("time must not be empty".to_string());
    }
    let parts: Vec<&str> = value.split(':').collect();
    if parts.len() != 2 {
        return Err(format!("time must be HH:MM, got {raw:?}"));
    }
    let hour: i32 = parts[0]
        .trim()
        .parse()
        .map_err(|_| format!("invalid hour in {raw:?}"))?;
    let minute: i32 = parts[1]
        .trim()
        .parse()
        .map_err(|_| format!("invalid minute in {raw:?}"))?;
    if !(0..=23).contains(&hour) {
        return Err(format!("invalid hour in {raw:?}"));
    }
    if !(0..=59).contains(&minute) {
        return Err(format!("invalid minute in {raw:?}"));
    }
    Ok(hour * 60 + minute)
}

fn parse_schedule_weekdays(days: &[String]) -> Result<(), String> {
    for raw in days {
        let key: String = raw.trim().to_lowercase().chars().take(3).collect();
        if !WEEKDAY_KEYS.iter().any(|candidate| *candidate == key) {
            return Err(format!("invalid weekday {raw:?}"));
        }
    }
    Ok(())
}

/// A subscription rule source.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct FilterList {
    pub id: String,
    pub name: String,
    pub url: String,
    pub enabled: bool,
    pub rules_count: i32,
    pub last_updated: i64,
    pub checksum: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub etag: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub last_modified: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub last_status: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub last_error: String,
}

/// Built-in default subscription list.
pub fn default_subscription_lists() -> Vec<FilterList> {
    vec![FilterList {
        id: "adguard-dns-filter".to_string(),
        name: "AdGuard DNS Filter".to_string(),
        url: "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt".to_string(),
        enabled: true,
        rules_count: 0,
        last_updated: 0,
        ..FilterList::default()
    }]
}

fn de_filter_lists<'de, D>(deserializer: D) -> Result<Vec<FilterList>, D::Error>
where
    D: Deserializer<'de>,
{
    // Go unmarshals `null` into a nil slice, which NormalizeFilterConfig then replaces with the
    // built-in list. A missing key is already handled by the container default.
    Ok(Option::<Vec<FilterList>>::deserialize(deserializer)?
        .unwrap_or_else(default_subscription_lists))
}

/// Rule filter engine configuration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct FilterConfig {
    pub enabled: bool,
    pub block_mode: String,
    #[serde(rename = "blockingIPv4")]
    pub blocking_ipv4: String,
    #[serde(rename = "blockingIPv6")]
    pub blocking_ipv6: String,
    #[serde(deserialize_with = "nullable_vec")]
    pub custom_rules: Vec<String>,
    #[serde(deserialize_with = "de_filter_lists")]
    pub lists: Vec<FilterList>,
    pub update_interval_hours: i32,
    pub data_dir: String,
    pub schedule_enabled: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub schedules: Vec<BlockingSchedule>,
    pub filter_response: bool,
    pub allowlist_only: bool,
    pub bogus_nx_domain: bool,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub bogus_nx_domain_networks: Vec<String>,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub blocked_services: Vec<String>,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub blocked_service_groups: Vec<String>,
    #[serde(
        skip_serializing_if = "HashMap::is_empty",
        deserialize_with = "nullable_map"
    )]
    pub service_schedules: HashMap<String, Vec<BlockingSchedule>>,
}

impl Default for FilterConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            block_mode: BLOCK_MODE_NULL_IP.to_string(),
            blocking_ipv4: DEFAULT_BLOCKING_IPV4.to_string(),
            blocking_ipv6: DEFAULT_BLOCKING_IPV6.to_string(),
            custom_rules: Vec::new(),
            lists: default_subscription_lists(),
            update_interval_hours: DEFAULT_UPDATE_INTERVAL_HOURS,
            data_dir: default_filter_dir().to_string_lossy().into_owned(),
            schedule_enabled: false,
            schedules: Vec::new(),
            filter_response: false,
            allowlist_only: false,
            bogus_nx_domain: false,
            bogus_nx_domain_networks: default_bogus_nx_domain_networks(),
            blocked_services: Vec::new(),
            blocked_service_groups: Vec::new(),
            service_schedules: HashMap::new(),
        }
    }
}

impl FilterConfig {
    /// Mirror `NormalizeFilterConfig`.
    ///
    /// One deliberate deviation: the Go code drops service/group ids that are absent from the
    /// embedded `services.json` catalog. The catalog is runtime data owned by the rule engine,
    /// not part of this model crate, so unknown ids are retained here (trimmed and deduplicated)
    /// and catalog validation is left to the service that owns the catalog. Dropping them here
    /// would silently delete user selections.
    pub fn normalize(&mut self) {
        if self.block_mode.is_empty() {
            self.block_mode = BLOCK_MODE_NULL_IP.to_string();
        }
        if self.blocking_ipv4.is_empty() {
            self.blocking_ipv4 = DEFAULT_BLOCKING_IPV4.to_string();
        }
        if self.blocking_ipv6.is_empty() {
            self.blocking_ipv6 = DEFAULT_BLOCKING_IPV6.to_string();
        }
        if self.update_interval_hours <= 0 {
            self.update_interval_hours = DEFAULT_UPDATE_INTERVAL_HOURS;
        }
        if self.data_dir.is_empty() {
            self.data_dir = default_filter_dir().to_string_lossy().into_owned();
        }
        retain_valid_schedules(&mut self.schedules);

        // Only whitespace/dedup, like the Go implementation: validity is reported by the matcher
        // compiler, which can produce a useful error message.
        self.bogus_nx_domain_networks =
            trim_dedup_ci(std::mem::take(&mut self.bogus_nx_domain_networks));
        self.blocked_services = trim_dedup(std::mem::take(&mut self.blocked_services));
        self.blocked_service_groups = trim_dedup(std::mem::take(&mut self.blocked_service_groups));
        self.service_schedules =
            normalize_service_schedules(std::mem::take(&mut self.service_schedules));
    }
}

/// Retain schedules that pass validation.
pub fn retain_valid_schedules(schedules: &mut Vec<BlockingSchedule>) {
    schedules.retain_mut(|schedule| schedule.normalize().is_ok());
}

fn trim_dedup(values: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::with_capacity(values.len());
    for raw in values {
        let value = raw.trim().to_string();
        if value.is_empty() || !seen.insert(value.clone()) {
            continue;
        }
        out.push(value);
    }
    out
}

fn trim_dedup_ci(values: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::with_capacity(values.len());
    for raw in values {
        let value = raw.trim().to_string();
        if value.is_empty() || !seen.insert(value.to_lowercase()) {
            continue;
        }
        out.push(value);
    }
    out
}

fn normalize_service_schedules(
    schedules: HashMap<String, Vec<BlockingSchedule>>,
) -> HashMap<String, Vec<BlockingSchedule>> {
    let mut out = HashMap::new();
    for (raw_id, mut list) in schedules {
        let id = raw_id.trim().to_string();
        if id.is_empty() {
            continue;
        }
        retain_valid_schedules(&mut list);
        if list.is_empty() {
            continue;
        }
        out.insert(id, list);
    }
    out
}

/// The built-in "bogus NXDOMAIN" address set used as a default.
pub fn default_bogus_nx_domain_networks() -> Vec<String> {
    vec![
        "0.0.0.0/8".to_string(),
        "::/128".to_string(),
        "127.0.0.0/8".to_string(),
        "::1/128".to_string(),
    ]
}

/// Validate a blocking mode.
pub fn is_valid_block_mode(mode: &str) -> bool {
    matches!(
        mode,
        BLOCK_MODE_NULL_IP | BLOCK_MODE_NXDOMAIN | BLOCK_MODE_REFUSED
    )
}
