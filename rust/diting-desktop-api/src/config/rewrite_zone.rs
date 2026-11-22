use serde::{Deserialize, Serialize};

use super::serde_util::{is_zero_u32, nullable_vec};

pub const DEFAULT_REWRITE_TTL: u32 = 60;
pub const DEFAULT_ZONE_TTL: u32 = 300;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct RewriteRecord {
    #[serde(rename = "type")]
    pub kind: String,
    pub value: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct RewriteRule {
    pub domain: String,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub ips: Vec<String>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub cname: String,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub txt: Vec<String>,
    #[serde(skip_serializing_if = "is_zero_u32")]
    pub ttl: u32,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub records: Vec<RewriteRecord>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub rcode: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct RewriteConfig {
    pub enabled: bool,
    pub ttl: u32,
    #[serde(deserialize_with = "nullable_vec")]
    pub rules: Vec<RewriteRule>,
}

impl Default for RewriteConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            ttl: DEFAULT_REWRITE_TTL,
            rules: Vec::new(),
        }
    }
}

impl RewriteConfig {
    pub fn normalize(&mut self) {
        if self.ttl == 0 {
            self.ttl = DEFAULT_REWRITE_TTL;
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ZoneEntry {
    pub id: String,
    pub origin: String,
    pub content: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ZoneConfig {
    pub enabled: bool,
    pub ttl: u32,
    #[serde(deserialize_with = "nullable_vec")]
    pub zones: Vec<ZoneEntry>,
}

impl Default for ZoneConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            ttl: DEFAULT_ZONE_TTL,
            zones: Vec::new(),
        }
    }
}

impl ZoneConfig {
    pub fn normalize(&mut self) {
        if self.ttl == 0 {
            self.ttl = DEFAULT_ZONE_TTL;
        }
        for (index, zone) in self.zones.iter_mut().enumerate() {
            zone.origin = zone.origin.trim().to_string();
            zone.id = zone.id.trim().to_string();
            if zone.id.is_empty() {
                zone.id = format!("zone-{}-{}", super::timestamp_nanos(), index);
            }
        }
    }
}
