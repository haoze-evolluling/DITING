//! Request/response payloads that belong to the HTTP contract rather than the controllers.

use serde::{Deserialize, Serialize};

/// `ipc.MetaResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MetaResponse {
    pub os: String,
}

/// `ipc.AuthStatusResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStatusResponse {
    pub initialized: bool,
    pub web_enabled: bool,
    pub authenticated: bool,
    pub username: String,
    pub locked: bool,
    pub lockout_remaining_sec: i64,
}

/// `ipc.LoginRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginRequest {
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
}

/// `ipc.LoginResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginResponse {
    pub token: String,
    pub username: String,
    pub expires_at: i64,
}

/// `ipc.SetupAuthRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupAuthRequest {
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
}

/// `ipc.ChangePasswordRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangePasswordRequest {
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub old_password: String,
    #[serde(default)]
    pub new_password: String,
}

/// `ipc.AutofixPortRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutofixPortRequest {
    #[serde(default, rename = "startDNS")]
    pub start_dns: bool,
}

/// `ipc.SetLoginBackgroundRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetLoginBackgroundRequest {
    #[serde(default, rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub opacity: i32,
    #[serde(default)]
    pub blur: i32,
    #[serde(default)]
    pub admin_password: String,
}

/// `ipc.ParseStampRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParseStampRequest {
    #[serde(default)]
    pub stamp: String,
}

/// `ipc.StampProps`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StampProps {
    #[serde(rename = "dnssec")]
    pub dnssec: bool,
    #[serde(rename = "noLog")]
    pub no_log: bool,
    #[serde(rename = "noFilter")]
    pub no_filter: bool,
}

/// `ipc.ParseStampResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParseStampResponse {
    pub protocol: String,
    pub server: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub url: String,
    pub provider_name: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub path: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub server_addr: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub bootstrap_ips: Vec<String>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub pin: String,
    pub props: StampProps,
    pub proto_name: String,
}
