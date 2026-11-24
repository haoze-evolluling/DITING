use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetaResponse {
    pub os: String,
    pub storage_backend: String,
    pub database_path: Option<String>,
}

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

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginRequest {
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginResponse {
    pub token: String,
    pub username: String,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupAuthRequest {
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResetPasswordRequest {
    #[serde(default)]
    pub new_password: String,
}

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

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutofixPortRequest {
    #[serde(default, rename = "startDNS")]
    pub start_dns: bool,
}

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

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParseStampRequest {
    #[serde(default)]
    pub stamp: String,
}

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
