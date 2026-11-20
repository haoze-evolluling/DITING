use serde::{Deserialize, Serialize};

use super::serde_util::nullable_vec;

pub const DEFAULT_SAFESEARCH_TTL: u32 = 300;
pub const DEFAULT_SAFEBROWSING_TIMEOUT_MS: i32 = 3000;
pub const DEFAULT_SAFEBROWSING_CACHE_SIZE: i32 = 10_000;
pub const DEFAULT_SAFEBROWSING_CACHE_TTL: i32 = 600;

pub const DEFAULT_DOT_PORT: i32 = 853;
pub const DEFAULT_DOH_PORT: i32 = 443;
pub const DEFAULT_DOQ_PORT: i32 = 853;
pub const DEFAULT_DOH_PATH: &str = "/dns-query";
pub const DEFAULT_SERVER_NAME: &str = "dns.lan";

pub const CERT_SOURCE_SELF_SIGNED: &str = "self_signed";
pub const CERT_SOURCE_FILE: &str = "file";
pub const CERT_SOURCE_PKCS12: &str = "pkcs12";

pub const SAFESEARCH_SERVICES: [&str; 7] = [
    "bing",
    "duckduckgo",
    "ecosia",
    "google",
    "pixabay",
    "yandex",
    "youtube",
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SafeSearchConfig {
    pub enabled: bool,
    #[serde(
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "nullable_vec"
    )]
    pub disabled: Vec<String>,
    pub ttl: u32,
}

impl Default for SafeSearchConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            disabled: Vec::new(),
            ttl: DEFAULT_SAFESEARCH_TTL,
        }
    }
}

impl SafeSearchConfig {
    pub fn normalize(&mut self) {
        if self.ttl == 0 {
            self.ttl = DEFAULT_SAFESEARCH_TTL;
        }
        let mut seen = std::collections::HashSet::new();
        self.disabled.retain(|service| {
            SAFESEARCH_SERVICES.contains(&service.as_str()) && seen.insert(service.clone())
        });
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SafeBrowsingConfig {
    pub enabled: bool,
    pub parental_enabled: bool,
    pub timeout_ms: i32,
    pub cache_size: i32,
    #[serde(rename = "cacheTTLSeconds")]
    pub cache_ttl_seconds: i32,
}

impl Default for SafeBrowsingConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            parental_enabled: false,
            timeout_ms: DEFAULT_SAFEBROWSING_TIMEOUT_MS,
            cache_size: DEFAULT_SAFEBROWSING_CACHE_SIZE,
            cache_ttl_seconds: DEFAULT_SAFEBROWSING_CACHE_TTL,
        }
    }
}

impl SafeBrowsingConfig {
    pub fn normalize(&mut self) {
        if !(100..=30_000).contains(&self.timeout_ms) {
            self.timeout_ms = DEFAULT_SAFEBROWSING_TIMEOUT_MS;
        }
        if self.cache_size < 0 {
            self.cache_size = 0;
        }
        if self.cache_ttl_seconds <= 0 {
            self.cache_ttl_seconds = DEFAULT_SAFEBROWSING_CACHE_TTL;
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct CertConfig {
    pub source: String,
    pub cert_file: String,
    pub key_file: String,
    pub pkcs12_password: String,
    pub key_type: String,
    pub common_name: String,
    #[serde(deserialize_with = "nullable_vec")]
    pub dns_names: Vec<String>,
    #[serde(rename = "ipAddresses", deserialize_with = "nullable_vec")]
    pub ip_addresses: Vec<String>,
    pub valid_days: i32,
}

impl Default for CertConfig {
    fn default() -> Self {
        Self {
            source: CERT_SOURCE_SELF_SIGNED.to_string(),
            cert_file: String::new(),
            key_file: String::new(),
            pkcs12_password: String::new(),
            key_type: "ecdsa".to_string(),
            common_name: DEFAULT_SERVER_NAME.to_string(),
            dns_names: vec![DEFAULT_SERVER_NAME.to_string()],
            ip_addresses: Vec::new(),
            valid_days: 825,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ReverseProxyConfig {
    pub enabled: bool,
    #[serde(deserialize_with = "nullable_vec")]
    pub trusted_sources: Vec<String>,
    pub client_ip_header: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct EncryptedDNSConfig {
    pub enabled: bool,
    pub cert: CertConfig,
    pub dot_enabled: bool,
    pub doh_enabled: bool,
    pub doq_enabled: bool,
    pub listen_address: String,
    pub dot_port: i32,
    pub doh_port: i32,
    pub doq_port: i32,
    pub doh_path: String,
    pub server_name: String,
    pub ddr_enabled: bool,
    pub uuid: String,
    pub reverse_proxy: ReverseProxyConfig,
}

impl Default for EncryptedDNSConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            cert: CertConfig::default(),
            dot_enabled: false,
            doh_enabled: false,
            doq_enabled: false,
            listen_address: String::new(),
            dot_port: DEFAULT_DOT_PORT,
            doh_port: DEFAULT_DOH_PORT,
            doq_port: DEFAULT_DOQ_PORT,
            doh_path: DEFAULT_DOH_PATH.to_string(),
            server_name: DEFAULT_SERVER_NAME.to_string(),
            ddr_enabled: false,
            uuid: String::new(),
            reverse_proxy: ReverseProxyConfig::default(),
        }
    }
}

impl EncryptedDNSConfig {
    pub fn normalize(&mut self) {
        normalize_cert_config(&mut self.cert);

        self.listen_address = self.listen_address.trim().to_string();
        self.server_name = self.server_name.trim().to_string();
        if self.server_name.is_empty() {
            self.server_name = DEFAULT_SERVER_NAME.to_string();
        }
        self.uuid = self.uuid.trim().to_string();

        self.reverse_proxy.trusted_sources = trim_non_empty(&self.reverse_proxy.trusted_sources);
        self.reverse_proxy.client_ip_header =
            self.reverse_proxy.client_ip_header.trim().to_string();

        if !is_valid_port(self.dot_port) {
            self.dot_port = DEFAULT_DOT_PORT;
        }
        if !is_valid_port(self.doh_port) {
            self.doh_port = DEFAULT_DOH_PORT;
        }
        if !is_valid_port(self.doq_port) {
            self.doq_port = DEFAULT_DOQ_PORT;
        }

        self.doh_path = self.doh_path.trim().to_string();
        if self.doh_path.is_empty() {
            self.doh_path = DEFAULT_DOH_PATH.to_string();
        } else if !self.doh_path.starts_with('/') {
            self.doh_path = format!("/{}", self.doh_path);
        }
    }
}

pub fn normalize_cert_config(cert: &mut CertConfig) {
    if !is_valid_cert_source(&cert.source) {
        cert.source = CERT_SOURCE_SELF_SIGNED.to_string();
    }
    if cert.key_type != "rsa" && cert.key_type != "ecdsa" {
        cert.key_type = "ecdsa".to_string();
    }
    if !(1..=3650).contains(&cert.valid_days) {
        cert.valid_days = 825;
    }
    cert.cert_file = cert.cert_file.trim().to_string();
    cert.key_file = cert.key_file.trim().to_string();
    cert.common_name = cert.common_name.trim().to_string();
    cert.dns_names = trim_non_empty(&cert.dns_names);
    cert.ip_addresses = trim_non_empty(&cert.ip_addresses);
}

pub fn is_valid_cert_source(source: &str) -> bool {
    matches!(
        source,
        CERT_SOURCE_SELF_SIGNED | CERT_SOURCE_FILE | CERT_SOURCE_PKCS12
    )
}

fn is_valid_port(port: i32) -> bool {
    (1..=65535).contains(&port)
}

fn trim_non_empty(values: &[String]) -> Vec<String> {
    values
        .iter()
        .filter_map(|value| {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        })
        .collect()
}
