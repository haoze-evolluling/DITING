use serde::{Deserialize, Deserializer, Serialize};

use super::duration::{self, DurationValue};
use super::serde_util::nullable_vec;

pub const ANY_MODE_NOTIMP: &str = "notimp";
pub const ANY_MODE_RFC8482: &str = "rfc8482";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DNSConfig {
    #[serde(deserialize_with = "nullable_vec")]
    pub udp_addresses: Vec<String>,
    #[serde(deserialize_with = "nullable_vec")]
    pub tcp_addresses: Vec<String>,
    #[serde(deserialize_with = "de_read_timeout")]
    pub read_timeout: DurationValue,
    #[serde(deserialize_with = "de_write_timeout")]
    pub write_timeout: DurationValue,
    #[serde(rename = "allowLAN")]
    pub allow_lan: bool,
    #[serde(rename = "enableEDE")]
    pub enable_ede: bool,
    pub block_unqualified: bool,
    #[serde(rename = "blockPrivatePTR")]
    pub block_private_ptr: bool,
    #[serde(rename = "blockIPv6")]
    pub block_ipv6: bool,
    #[serde(rename = "blockECH")]
    pub block_ech: bool,
    pub edns_padding: i32,
    #[serde(rename = "blockANY")]
    pub block_any: bool,
    #[serde(rename = "blockANYMode")]
    pub block_any_mode: String,
}

impl Default for DNSConfig {
    fn default() -> Self {
        Self {
            udp_addresses: vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()],
            tcp_addresses: vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()],
            read_timeout: DurationValue::from_secs(5),
            write_timeout: DurationValue::from_secs(5),
            allow_lan: false,
            enable_ede: true,
            block_unqualified: false,
            block_private_ptr: true,
            block_ipv6: false,
            block_ech: false,
            edns_padding: 128,
            block_any: false,
            block_any_mode: ANY_MODE_NOTIMP.to_string(),
        }
    }
}

impl DNSConfig {
    pub fn normalize(&mut self) {
        if self.udp_addresses.is_empty() && self.tcp_addresses.is_empty() {
            self.udp_addresses = vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()];
            self.tcp_addresses = vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()];
        }
        if self.read_timeout.0 <= 0 {
            self.read_timeout = DurationValue::from_secs(5);
        }
        if self.write_timeout.0 <= 0 {
            self.write_timeout = DurationValue::from_secs(5);
        }
        if self.edns_padding < 0 {
            self.edns_padding = 0;
        }
        if self.block_any_mode != ANY_MODE_NOTIMP && self.block_any_mode != ANY_MODE_RFC8482 {
            self.block_any_mode = ANY_MODE_NOTIMP.to_string();
        }
    }
}

fn de_read_timeout<'de, D>(deserializer: D) -> Result<DurationValue, D::Error>
where
    D: Deserializer<'de>,
{
    duration::deserialize_or_default(deserializer, DurationValue::from_secs(5))
}

fn de_write_timeout<'de, D>(deserializer: D) -> Result<DurationValue, D::Error>
where
    D: Deserializer<'de>,
{
    duration::deserialize_or_default(deserializer, DurationValue::from_secs(5))
}

fn de_session_timeout<'de, D>(deserializer: D) -> Result<DurationValue, D::Error>
where
    D: Deserializer<'de>,
{
    duration::deserialize_or_default(deserializer, DurationValue::from_hours(7 * 24))
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct IPCConfig {
    pub listen_address: String,
    pub auth_token: String,
}

impl Default for IPCConfig {
    fn default() -> Self {
        Self {
            listen_address: "127.0.0.1:15353".to_string(),
            auth_token: String::new(),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct TakeoverConfig {
    pub auto_takeover_on_start: bool,
    pub state_file_path: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct LoginBgConfig {
    #[serde(rename = "type")]
    pub kind: String,
    pub url: String,
    pub opacity: i32,
    pub blur: i32,
    pub updated_at: i64,
}

impl Default for LoginBgConfig {
    fn default() -> Self {
        Self {
            kind: "none".to_string(),
            url: String::new(),
            opacity: 40,
            blur: 0,
            updated_at: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct WebConfig {
    pub enabled: bool,
    pub listen_port: i32,
    pub username: String,
    pub password_hash: String,
    pub salt: String,
    #[serde(deserialize_with = "de_session_timeout")]
    pub session_timeout: DurationValue,
    pub background: LoginBgConfig,
}

impl Default for WebConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            listen_port: 15353,
            username: "admin".to_string(),
            password_hash: String::new(),
            salt: String::new(),
            session_timeout: DurationValue::from_hours(7 * 24),
            background: LoginBgConfig::default(),
        }
    }
}

impl WebConfig {
    pub fn normalize(&mut self) {
        if self.listen_port <= 0 {
            self.listen_port = 15353;
        }
        if self.background.opacity <= 0 && self.background.kind.is_empty() {
            self.background.opacity = 40;
        }
        self.background.opacity = self.background.opacity.clamp(0, 100);
        self.background.blur = self.background.blur.clamp(0, 20);
    }
}
