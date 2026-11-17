//! Encrypted DNS configuration, certificates and Apple profiles.

use std::net::IpAddr;

use serde::{Deserialize, Serialize};

use diting_desktop_api::config::security::{
    normalize_cert_config, CertConfig, EncryptedDNSConfig, ReverseProxyConfig,
    CERT_SOURCE_SELF_SIGNED, DEFAULT_DOH_PATH, DEFAULT_DOH_PORT, DEFAULT_DOQ_PORT,
    DEFAULT_DOT_PORT,
};
use diting_desktop_api::config::Config;
use diting_desktop_core::cert::{CertHealth, CertInfo};
use diting_desktop_core::mobileconfig::{
    build_mobile_config, MobileConfigOptions, MOBILE_CONFIG_CONTENT_TYPE, MOBILE_CONFIG_FILE_EXT,
    PROTOCOL_HTTPS, PROTOCOL_TLS,
};

use crate::controller::ControllerError;
use crate::AppRuntime;

/// `ipc.ConfigureEncryptedDNSRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureEncryptedDNSRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub dot_enabled: Option<bool>,
    #[serde(default)]
    pub doh_enabled: Option<bool>,
    #[serde(default)]
    pub doq_enabled: Option<bool>,
    #[serde(default)]
    pub ddr_enabled: Option<bool>,
    #[serde(default)]
    pub listen_address: Option<String>,
    #[serde(default)]
    pub dot_port: Option<i32>,
    #[serde(default)]
    pub doh_port: Option<i32>,
    #[serde(default)]
    pub doq_port: Option<i32>,
    #[serde(default)]
    pub doh_path: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub cert: Option<CertConfig>,
}

/// `ipc.GenerateCertRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerateCertRequest {
    #[serde(default)]
    pub key_type: String,
    #[serde(default)]
    pub common_name: String,
    #[serde(default)]
    pub dns_names: Vec<String>,
    #[serde(default)]
    pub ip_addresses: Vec<String>,
    #[serde(default)]
    pub valid_days: i32,
    #[serde(default)]
    pub force: bool,
}

/// `ipc.ImportCertRequest` after base64 decoding (the IPC layer owns the base64 codec).
#[derive(Debug, Clone, Default)]
pub struct ImportCertRequest {
    pub mode: String,
    pub cert_pem: String,
    pub key_pem: String,
    pub data: Vec<u8>,
    pub password: String,
}

/// `ipc.ConfigureACLRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureACLRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub trusted_sources: Option<Vec<String>>,
    #[serde(default)]
    pub client_ip_header: Option<String>,
    #[serde(default)]
    pub confirm_unrestricted: bool,
}

/// `core.CertInfo` wire shape.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CertInfoDto {
    pub source: String,
    pub subject: String,
    pub issuer: String,
    pub serial_number: String,
    pub not_before: String,
    pub not_after: String,
    pub dns_names: Vec<String>,
    pub ip_addresses: Vec<String>,
    pub days_remaining: i64,
    pub fingerprint: String,
    pub chain_length: i64,
    pub loaded: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub error: String,
    pub self_signed: bool,
}

impl From<CertInfo> for CertInfoDto {
    fn from(info: CertInfo) -> Self {
        Self {
            source: info.source,
            subject: info.subject,
            issuer: info.issuer,
            serial_number: info.serial_number,
            not_before: info.not_before,
            not_after: info.not_after,
            dns_names: info.dns_names,
            ip_addresses: info.ip_addresses,
            days_remaining: info.days_remaining,
            fingerprint: info.fingerprint,
            chain_length: info.chain_length,
            loaded: info.loaded,
            error: info.error,
            self_signed: info.self_signed,
        }
    }
}

/// `ipc.EncryptedDNSStatusResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedDNSStatusResponse {
    pub config: EncryptedDNSConfig,
    pub cert: CertInfoDto,
    pub cert_dir: String,
    pub default_dot_port: i32,
    pub default_doh_port: i32,
    pub default_doq_port: i32,
    pub default_doh_path: String,
    pub dot_listen: String,
    pub doh_listen: String,
    pub doq_listen: String,
    pub doh_urls: Vec<String>,
    pub unrestricted_trust: bool,
    pub cert_expires_soon: bool,
    pub cert_expired: bool,
}

/// Certificate import mode tokens.
pub const CERT_IMPORT_MODE_PEM: &str = "pem";
pub const CERT_IMPORT_MODE_PKCS12: &str = "pkcs12";

/// Mobile config binary plus the headers the raw endpoint needs.
pub struct MobileConfig {
    pub data: Vec<u8>,
    pub content_type: &'static str,
    pub file_ext: &'static str,
}

/// Fills in SANs only when the caller supplied none, like `DeriveCertNames` in the Go controller.
fn derive_cert_names(config: &mut CertConfig, server_name: &str, listen_address: &str) {
    if config.dns_names.is_empty() && config.ip_addresses.is_empty() {
        let (dns_names, ip_addresses) =
            diting_desktop_core::cert::derive_cert_names(server_name, listen_address);
        config.dns_names = dns_names;
        config.ip_addresses = ip_addresses;
    }
}

/// Whether a trusted-source entry trusts the whole Internet.
pub fn is_unrestricted_trust(entry: &str) -> bool {
    let trimmed = entry.trim();
    trimmed == "0.0.0.0/0" || trimmed == "::/0"
}

/// Normalizes and validates the reverse-proxy trusted source list.
pub fn normalize_trusted_sources(entries: &[String]) -> Result<Vec<String>, String> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for raw in entries {
        let entry = raw.trim();
        if entry.is_empty() {
            continue;
        }
        if let Some((address, prefix)) = entry.split_once('/') {
            let ip: IpAddr = address
                .parse()
                .map_err(|_| format!("可信来源网段 {entry:?} 无效"))?;
            let prefix: u32 = prefix
                .parse()
                .map_err(|_| format!("可信来源网段 {entry:?} 无效"))?;
            let max = if ip.is_ipv4() { 32 } else { 128 };
            if prefix > max {
                return Err(format!("可信来源网段 {entry:?} 无效"));
            }
        } else if entry.parse::<IpAddr>().is_err() {
            return Err(format!("可信来源 {entry:?} 不是合法的 IP 或 CIDR"));
        }
        if seen.insert(entry.to_string()) {
            out.push(entry.to_string());
        }
    }
    Ok(out)
}

pub fn has_unrestricted_trust(entries: &[String]) -> bool {
    entries.iter().any(|entry| is_unrestricted_trust(entry))
}

/// Stable UUID-ish identifier derived from the clock; profile identity only, not security.
fn new_profile_uuid() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let high = (nanos >> 64) as u32;
    let low = nanos as u64;
    format!(
        "{:08x}-{:04x}-4{:03x}-a{:03x}-{:012x}",
        high,
        (low >> 48) as u16,
        (low >> 36) & 0x0fff,
        (low >> 24) & 0x0fff,
        low & 0xffff_ffff_ffff
    )
}

impl AppRuntime {
    fn doh_urls(&self, config: &EncryptedDNSConfig) -> Vec<String> {
        let port = if config.doh_port > 0 {
            config.doh_port
        } else {
            DEFAULT_DOH_PORT
        };
        let path = if config.doh_path.trim().is_empty() {
            DEFAULT_DOH_PATH.to_string()
        } else {
            config.doh_path.clone()
        };
        let mut hosts = Vec::new();
        if !config.server_name.trim().is_empty() {
            hosts.push(config.server_name.trim().to_string());
        }
        for address in self.lan_addresses() {
            if !hosts.contains(&address) {
                hosts.push(address);
            }
        }
        hosts
            .into_iter()
            .map(|host| {
                if host.contains(':') && !host.starts_with('[') {
                    format!("https://[{host}]:{port}{path}")
                } else {
                    format!("https://{host}:{port}{path}")
                }
            })
            .collect()
    }

    /// `GetEncryptedDNS`.
    pub fn encrypted_dns_status(&self) -> EncryptedDNSStatusResponse {
        let config = self.config().encrypted;
        self.cert.reload();
        let info = self.cert.info();
        let health: CertHealth = self.cert.health();
        let (dot_listen, doh_listen, doq_listen) = self.encrypted_addresses();
        EncryptedDNSStatusResponse {
            doh_urls: self.doh_urls(&config),
            config,
            cert: info.into(),
            cert_dir: self.cert.dir().to_string_lossy().into_owned(),
            default_dot_port: DEFAULT_DOT_PORT,
            default_doh_port: DEFAULT_DOH_PORT,
            default_doq_port: DEFAULT_DOQ_PORT,
            default_doh_path: DEFAULT_DOH_PATH.to_string(),
            dot_listen: dot_listen.unwrap_or_default(),
            doh_listen: doh_listen.unwrap_or_default(),
            doq_listen: doq_listen.unwrap_or_default(),
            unrestricted_trust: has_unrestricted_trust(
                &self.config().encrypted.reverse_proxy.trusted_sources,
            ),
            cert_expires_soon: health.expires_soon,
            cert_expired: health.expired,
        }
    }

    /// `ConfigureEncryptedDNS`.
    pub fn configure_encrypted_dns(
        &self,
        request: ConfigureEncryptedDNSRequest,
    ) -> Result<(), ControllerError> {
        let mut config = self.config();
        let mut encrypted = config.encrypted.clone();
        if let Some(value) = request.enabled {
            encrypted.enabled = value;
        }
        if let Some(value) = request.dot_enabled {
            encrypted.dot_enabled = value;
        }
        if let Some(value) = request.doh_enabled {
            encrypted.doh_enabled = value;
        }
        if let Some(value) = request.doq_enabled {
            encrypted.doq_enabled = value;
        }
        if let Some(value) = request.ddr_enabled {
            encrypted.ddr_enabled = value;
        }
        if let Some(value) = request.listen_address {
            encrypted.listen_address = value;
        }
        if let Some(value) = request.dot_port {
            encrypted.dot_port = value;
        }
        if let Some(value) = request.doh_port {
            encrypted.doh_port = value;
        }
        if let Some(value) = request.doq_port {
            encrypted.doq_port = value;
        }
        if let Some(value) = request.doh_path {
            encrypted.doh_path = value;
        }
        if let Some(value) = request.server_name {
            encrypted.server_name = value;
        }
        if let Some(value) = request.cert {
            encrypted.cert = value;
        }
        encrypted.normalize();

        if (encrypted.cert.source == CERT_SOURCE_SELF_SIGNED || encrypted.cert.source.is_empty())
            && !self.cert.info().loaded
        {
            let mut cert = encrypted.cert.clone();
            derive_cert_names(&mut cert, &encrypted.server_name, &encrypted.listen_address);
            if self.cert.ensure_self_signed(cert).is_ok() {
                encrypted.cert = self.cert.config();
            }
        }

        config.encrypted = encrypted;
        self.apply_config(config.clone());
        self.persist_config().map_err(ControllerError::new)
    }

    /// `GenerateEncryptedCert`.
    pub fn generate_encrypted_cert(
        &self,
        request: GenerateCertRequest,
    ) -> Result<(), ControllerError> {
        let config = self.config();
        let mut cert = config.encrypted.cert.clone();
        if !request.key_type.is_empty() {
            cert.key_type = request.key_type;
        }
        if !request.common_name.is_empty() {
            cert.common_name = request.common_name;
        }
        cert.dns_names = request.dns_names;
        cert.ip_addresses = request.ip_addresses;
        if request.valid_days > 0 {
            cert.valid_days = request.valid_days;
        }
        derive_cert_names(
            &mut cert,
            &config.encrypted.server_name,
            &config.encrypted.listen_address,
        );
        normalize_cert_config(&mut cert);

        if request.force {
            self.cert
                .regenerate_self_signed(cert)
                .map_err(ControllerError::new)?;
        } else {
            self.cert
                .ensure_self_signed(cert)
                .map_err(ControllerError::new)?;
        }
        let effective = self.cert.config();
        self.update_config(|next| next.encrypted.cert = effective)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    /// `ImportEncryptedCert` (PKCS#12 bodies are base64-decoded by the caller).
    pub fn import_encrypted_cert(&self, request: ImportCertRequest) -> Result<(), ControllerError> {
        match request.mode.as_str() {
            CERT_IMPORT_MODE_PEM => {
                if request.cert_pem.is_empty() || request.key_pem.is_empty() {
                    return Err(ControllerError::new("证书与私钥内容都不能为空"));
                }
                self.cert
                    .import_pem(request.cert_pem.as_bytes(), request.key_pem.as_bytes())
                    .map_err(ControllerError::new)?;
            }
            CERT_IMPORT_MODE_PKCS12 => {
                self.cert
                    .import_pkcs12(&request.data, &request.password)
                    .map_err(ControllerError::new)?;
            }
            other => {
                return Err(ControllerError::new(format!("不支持的导入方式: {other:?}")));
            }
        }
        let effective = self.cert.config();
        self.update_config(|next| next.encrypted.cert = effective)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    /// `ConfigureEncryptedACL`.
    pub fn configure_encrypted_acl(
        &self,
        request: ConfigureACLRequest,
    ) -> Result<(), ControllerError> {
        let mut config = self.config();
        let mut proxy: ReverseProxyConfig = config.encrypted.reverse_proxy.clone();
        if let Some(enabled) = request.enabled {
            proxy.enabled = enabled;
        }
        if let Some(header) = request.client_ip_header {
            proxy.client_ip_header = header;
        }
        if let Some(sources) = request.trusted_sources {
            let sources = normalize_trusted_sources(&sources).map_err(ControllerError::new)?;
            if !request.confirm_unrestricted && has_unrestricted_trust(&sources) {
                return Err(ControllerError::new(
                    "可信来源包含 0.0.0.0/0 或 ::/0：任何直连方都可伪造客户端来源，访问控制与限速会同时失效。请缩小范围，或显式确认接受该风险",
                ));
            }
            proxy.trusted_sources = sources;
        } else if !request.confirm_unrestricted && has_unrestricted_trust(&proxy.trusted_sources) {
            return Err(ControllerError::new(
                "可信来源包含 0.0.0.0/0 或 ::/0：任何直连方都可伪造客户端来源，访问控制与限速会同时失效。请缩小范围，或显式确认接受该风险",
            ));
        }
        config.encrypted.reverse_proxy = proxy;
        config.encrypted.normalize();
        self.apply_config(config.clone());
        self.persist_config().map_err(ControllerError::new)
    }

    /// `BuildEncryptedMobileConfig`.
    pub fn build_mobile_config(&self, protocol: &str) -> Result<MobileConfig, ControllerError> {
        let mut config: Config = self.config();
        if !config.encrypted.enabled {
            return Err(ControllerError::new("加密 DNS 服务未启用"));
        }
        let server_name = config.encrypted.server_name.trim().to_string();
        if server_name.is_empty() {
            return Err(ControllerError::new("尚未配置服务器名，无法生成描述文件"));
        }

        let requested = protocol.trim().to_ascii_uppercase();
        let chosen = if requested.is_empty() {
            if config.encrypted.doh_enabled {
                PROTOCOL_HTTPS.to_string()
            } else if config.encrypted.dot_enabled {
                PROTOCOL_TLS.to_string()
            } else {
                return Err(ControllerError::new(
                    "没有正在运行的加密监听器：请先启用 DoH 或 DoT 并确认端口已绑定",
                ));
            }
        } else {
            requested
        };

        let uuid = if config.encrypted.uuid.trim().is_empty() {
            let generated = new_profile_uuid();
            config.encrypted.uuid = generated.clone();
            self.update_config(|next| next.encrypted.uuid = generated.clone())
                .map_err(ControllerError::new)?;
            generated
        } else {
            config.encrypted.uuid.clone()
        };

        let server_url = if chosen == PROTOCOL_HTTPS {
            self.doh_urls(&config.encrypted)
                .into_iter()
                .next()
                .ok_or_else(|| {
                    ControllerError::new("无法构造 DoH 地址：请检查服务器名与端口配置")
                })?
        } else {
            String::new()
        };

        let options = MobileConfigOptions {
            server_name,
            server_url,
            protocol: chosen,
            display_name: "DITING 加密 DNS".to_string(),
            description: "由 DITING 提供的加密 DNS 解析配置".to_string(),
            uuid,
        };
        let data = build_mobile_config(&options).map_err(ControllerError::new)?;
        Ok(MobileConfig {
            data,
            content_type: MOBILE_CONFIG_CONTENT_TYPE,
            file_ext: MOBILE_CONFIG_FILE_EXT,
        })
    }
}
