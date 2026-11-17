//! Client identification, aliases and client groups.

use std::collections::HashSet;
use std::net::IpAddr;

use serde::{Deserialize, Deserializer, Serialize};

use super::duration::{self, DurationValue};
use super::filter::{is_valid_block_mode, retain_valid_schedules, BlockingSchedule};
use super::serde_util::{is_false, nullable_vec};

/// Group id used when no configured group matches a client.
pub const DEFAULT_CLIENT_GROUP_ID: &str = "default";

/// Static IP-to-name binding.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ClientAlias {
    pub ip: String,
    pub name: String,
}

/// Client identification configuration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ClientConfig {
    pub enabled: bool,
    #[serde(rename = "enableRDNS")]
    pub enable_rdns: bool,
    #[serde(rename = "cacheTTL", deserialize_with = "de_cache_ttl")]
    pub cache_ttl: DurationValue,
    #[serde(deserialize_with = "nullable_vec")]
    pub aliases: Vec<ClientAlias>,
    pub groups_enabled: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub groups: Vec<ClientGroup>,
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            enable_rdns: true,
            cache_ttl: DurationValue::from_hours(1),
            aliases: Vec::new(),
            groups_enabled: false,
            groups: Vec::new(),
        }
    }
}

fn de_cache_ttl<'de, D>(deserializer: D) -> Result<DurationValue, D::Error>
where
    D: Deserializer<'de>,
{
    duration::deserialize_or_default(deserializer, DurationValue::from_hours(1))
}

/// One client group with its own rule/upstream policy.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ClientGroup {
    pub id: String,
    pub name: String,
    pub enabled: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub clients: Vec<String>,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub rule_list_ids: Vec<String>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub block_mode: String,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub upstream_ids: Vec<String>,
    #[serde(skip_serializing_if = "is_false")]
    pub schedule_enabled: bool,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub schedules: Vec<BlockingSchedule>,
    #[serde(skip_serializing_if = "is_false")]
    pub allowlist_only: bool,
}

impl ClientConfig {
    /// Mirror `ClientConfig.Normalize` / `NormalizeClientGroupConfig`.
    ///
    /// As in Go, malformed entries are dropped rather than failing the whole config load. The
    /// problem list is not surfaced because `normalizeConfig` ignores it too.
    pub fn normalize(&mut self) {
        let mut seen_ids = HashSet::new();
        let mut kept = Vec::with_capacity(self.groups.len());

        for (index, mut group) in std::mem::take(&mut self.groups).into_iter().enumerate() {
            group.name = group.name.trim().to_string();
            group.id = group.id.trim().to_string();
            if group.id.is_empty() {
                group.id = format!("group-{}", index + 1);
            }
            if group.id == DEFAULT_CLIENT_GROUP_ID || !seen_ids.insert(group.id.clone()) {
                continue;
            }
            if group.name.is_empty() {
                group.name = group.id.clone();
            }

            group.clients.retain(|raw| {
                let member = raw.trim();
                !member.is_empty() && is_valid_ip_or_cidr(member)
            });
            for member in &mut group.clients {
                *member = member.trim().to_string();
            }

            group.upstream_ids = dedup_trimmed(group.upstream_ids);

            if !group.block_mode.is_empty() && !is_valid_block_mode(&group.block_mode) {
                group.block_mode.clear();
            }

            if group.schedules.is_empty() {
                group.schedule_enabled = false;
            } else {
                retain_valid_schedules(&mut group.schedules);
                if !group.schedules.iter().any(|schedule| schedule.enabled) {
                    group.schedule_enabled = false;
                }
            }

            kept.push(group);
        }

        self.groups = kept;
    }
}

fn dedup_trimmed(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
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

/// Validate an IP address or CIDR the way `parseIPOrCIDR` accepts them.
fn is_valid_ip_or_cidr(entry: &str) -> bool {
    if let Some((address, prefix)) = entry.split_once('/') {
        let Ok(ip) = address.parse::<IpAddr>() else {
            return false;
        };
        let Ok(prefix) = prefix.parse::<u32>() else {
            return false;
        };
        let max_prefix = if ip.is_ipv4() { 32 } else { 128 };
        prefix <= max_prefix
    } else {
        entry.parse::<IpAddr>().is_ok()
    }
}
