//! Platform value types mirrored from the former Go service's `internal/platform/types.go`.
//!
//! These are JSON/state-file DTOs only; the OS work lives in `diting-desktop-platform`. Field
//! names, `omitempty` markers and string constants match the Go definitions so IPC payloads and
//! the takeover state file stay wire-compatible.

use std::fmt;

use serde::{Deserialize, Serialize};

use crate::config::serde_util::nullable_vec;

/// Auto-start managed by a system service (starts before login).
pub const AUTO_START_MECHANISM_SERVICE: &str = "service";
/// Auto-start as a per-user login item.
pub const AUTO_START_MECHANISM_LOGIN_ITEM: &str = "login_item";
/// Auto-start through a systemd unit.
pub const AUTO_START_MECHANISM_SYSTEMD: &str = "systemd";
/// Auto-start through an XDG desktop entry.
pub const AUTO_START_MECHANISM_XDG: &str = "xdg";
/// No auto-start mechanism configured.
pub const AUTO_START_MECHANISM_NONE: &str = "none";

/// Core service is running.
pub const SERVICE_STATE_RUNNING: &str = "running";
/// Core service is stopped.
pub const SERVICE_STATE_STOPPED: &str = "stopped";
/// Core service is not installed.
pub const SERVICE_STATE_NOT_INSTALLED: &str = "not_installed";
/// Core service is starting.
pub const SERVICE_STATE_START_PENDING: &str = "start_pending";
/// Core service is stopping.
pub const SERVICE_STATE_STOP_PENDING: &str = "stop_pending";
/// Core service state could not be determined.
pub const SERVICE_STATE_UNKNOWN: &str = "unknown";

/// Network adapter properties and DNS configuration.
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

/// Original per-adapter configuration captured before takeover.
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

/// Persisted DNS takeover state used for crash recovery.
///
/// `timestamp` is Go's `time.Time`, serialized as RFC3339 text. It is kept as a string so a
/// state file written by the Go service round-trips unchanged without pulling in a date library.
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

/// Go's zero `time.Time` JSON representation.
fn zero_timestamp() -> String {
    "0001-01-01T00:00:00Z".to_string()
}

/// LAN address and the adapter that owns it.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LANAddressInfo {
    #[serde(default)]
    pub ip: String,
    #[serde(default)]
    pub interface_name: String,
    #[serde(default, rename = "isIPv6")]
    pub is_ipv6: bool,
}

/// Details of a process occupying a port.
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

/// Aggregate result of checking whether the DNS port is available.
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

/// Specialized port-conflict error carrying the diagnostic probe result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PortConflictError {
    pub result: Option<PortCheckResult>,
    pub message: Option<String>,
}

impl PortConflictError {
    /// Build from a probe result.
    pub fn from_result(result: PortCheckResult) -> Self {
        Self {
            result: Some(result),
            message: None,
        }
    }

    /// Build from an underlying error description.
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

/// Host auto-start management status.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutoStartStatus {
    #[serde(default)]
    pub enabled: bool,
    /// `service` / `login_item` / `systemd` / `xdg` / `none`.
    #[serde(default)]
    pub mechanism: String,
    #[serde(default)]
    pub detail: String,
}

/// Background core service status.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreServiceStatus {
    #[serde(default)]
    pub installed: bool,
    #[serde(default)]
    pub running: bool,
    /// See `SERVICE_STATE_*`.
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
    /// Absent from older service versions.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_start: Option<AutoStartStatus>,
}
