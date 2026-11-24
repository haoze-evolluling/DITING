use std::fmt;

use serde::{Deserialize, Serialize};

use crate::config::serde_util::nullable_vec;

pub const AUTO_START_MECHANISM_SERVICE: &str = "service";
pub const AUTO_START_MECHANISM_LOGIN_ITEM: &str = "login_item";
pub const AUTO_START_MECHANISM_SYSTEMD: &str = "systemd";
pub const AUTO_START_MECHANISM_PROCD: &str = "procd";
pub const AUTO_START_MECHANISM_XDG: &str = "xdg";
pub const AUTO_START_MECHANISM_NONE: &str = "none";

pub const SERVICE_STATE_RUNNING: &str = "running";
pub const SERVICE_STATE_STOPPED: &str = "stopped";
pub const SERVICE_STATE_NOT_INSTALLED: &str = "not_installed";
pub const SERVICE_STATE_START_PENDING: &str = "start_pending";
pub const SERVICE_STATE_STOP_PENDING: &str = "stop_pending";
pub const SERVICE_STATE_UNKNOWN: &str = "unknown";

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdapterInfo {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub index: i32,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub gateway: String,
    #[serde(default, rename = "ipv4DHCP")]
    pub ipv4_dhcp: bool,
    #[serde(default, rename = "ipv6DHCP")]
    pub ipv6_dhcp: bool,
    #[serde(default, rename = "ipv4DNS", deserialize_with = "nullable_vec")]
    pub ipv4_dns: Vec<String>,
    #[serde(default, rename = "ipv6DNS", deserialize_with = "nullable_vec")]
    pub ipv6_dns: Vec<String>,
    #[serde(default)]
    pub is_physical: bool,
    #[serde(default)]
    pub has_residual_loopback: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdapterState {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub index: i32,
    #[serde(default)]
    pub description: String,
    #[serde(default, rename = "ipv4DHCP")]
    pub ipv4_dhcp: bool,
    #[serde(default, rename = "ipv6DHCP")]
    pub ipv6_dhcp: bool,
    #[serde(default, rename = "ipv4DNS", deserialize_with = "nullable_vec")]
    pub ipv4_dns: Vec<String>,
    #[serde(default, rename = "ipv6DNS", deserialize_with = "nullable_vec")]
    pub ipv6_dns: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TakeoverState {
    #[serde(default)]
    pub active: bool,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub pid: i32,
    #[serde(default = "zero_timestamp")]
    pub timestamp: String,
    #[serde(default, deserialize_with = "nullable_vec")]
    pub adapters: Vec<AdapterState>,
}

impl Default for TakeoverState {
    fn default() -> Self {
        Self {
            active: false,
            version: String::new(),
            pid: 0,
            timestamp: zero_timestamp(),
            adapters: Vec::new(),
        }
    }
}

fn zero_timestamp() -> String {
    "0001-01-01T00:00:00Z".to_string()
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PortConflict {
    #[serde(default)]
    pub port: i32,
    #[serde(default)]
    pub protocol: String,
    #[serde(default)]
    pub local_address: String,
    #[serde(default)]
    pub pid: i32,
    #[serde(default)]
    pub process_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub service_name: String,
    #[serde(default, rename = "isICS")]
    pub is_ics: bool,
    #[serde(default)]
    pub is_self: bool,
    #[serde(default)]
    pub diagnosis: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PortCheckResult {
    #[serde(default)]
    pub available: bool,
    #[serde(default, deserialize_with = "nullable_vec")]
    pub conflicts: Vec<PortConflict>,
    #[serde(default, rename = "hasICS")]
    pub has_ics: bool,
    #[serde(default)]
    pub can_autofix: bool,
    #[serde(default)]
    pub diagnostic: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PortConflictError {
    pub result: Option<PortCheckResult>,
    pub message: Option<String>,
}

impl PortConflictError {
    pub fn from_result(result: PortCheckResult) -> Self {
        Self {
            result: Some(result),
            message: None,
        }
    }

    pub fn from_message(message: impl Into<String>) -> Self {
        Self {
            result: None,
            message: Some(message.into()),
        }
    }
}

impl fmt::Display for PortConflictError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        if let Some(result) = &self.result {
            if !result.diagnostic.is_empty() {
                return write!(formatter, "53 端口已被占用: {}", result.diagnostic);
            }
        }
        if let Some(message) = &self.message {
            return write!(formatter, "53 端口已被占用: {message}");
        }
        formatter.write_str("53 端口已被占用，无法启动 DNS 监听器")
    }
}

impl std::error::Error for PortConflictError {}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutoStartStatus {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub mechanism: String,
    #[serde(default)]
    pub detail: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreServiceStatus {
    #[serde(default)]
    pub installed: bool,
    #[serde(default)]
    pub running: bool,
    #[serde(default)]
    pub state: String,
    #[serde(default)]
    pub state_text: String,
    #[serde(default)]
    pub executable_path: String,
    #[serde(default)]
    pub is_elevated: bool,
    #[serde(default)]
    pub can_install: bool,
    #[serde(default)]
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_start: Option<AutoStartStatus>,
}
