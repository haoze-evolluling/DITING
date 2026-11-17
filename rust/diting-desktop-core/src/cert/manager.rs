//! Thread-safe certificate manager, ported from `cert_manager.go`.

use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use chrono::Utc;
use diting_desktop_api::config::security::{
    normalize_cert_config, CertConfig, CERT_SOURCE_FILE, CERT_SOURCE_SELF_SIGNED,
};
use serde::{Deserialize, Serialize};

use super::generate::generate_self_signed;
use super::health::{days_remaining, within_renewal_window, CertHealth};
use super::material::{
    decode_pkcs12, load_material, parse_chain, parse_pair, parse_private_key, resolve_paths,
    same_file_path, write_private, Material,
};
use super::{IMPORTED_CERT_FILE, IMPORTED_KEY_FILE, SELF_SIGNED_CERT_FILE, SELF_SIGNED_KEY_FILE};

/// Read-only certificate summary exposed to the UI (Go's `certInfo` DTO).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CertInfo {
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

struct State {
    dir: PathBuf,
    config: CertConfig,
    loaded: bool,
    load_error: Option<String>,
    material: Option<Material>,
}

/// Manages the encrypted-DNS server certificate.
///
/// Certificate material lives only on disk; the in-memory state keeps the parsed PEM so
/// [`CertManager::tls_config`] can rebuild a rustls configuration without re-reading files.
pub struct CertManager {
    inner: RwLock<State>,
}

impl CertManager {
    /// Create a manager and load whatever the configuration points at.
    pub fn new(dir: impl Into<PathBuf>, config: CertConfig) -> Self {
        let mut config = config;
        normalize_cert_config(&mut config);
        let manager = Self {
            inner: RwLock::new(State {
                dir: dir.into(),
                config,
                loaded: false,
                load_error: None,
                material: None,
            }),
        };
        manager.reload();
        manager
    }

    /// Replace the certificate configuration and reload the material.
    pub fn configure(&self, config: CertConfig) {
        let mut config = config;
        normalize_cert_config(&mut config);
        {
            let mut state = self.write_state();
            state.config = config;
        }
        self.reload();
    }

    /// Change the self-signed certificate directory without reloading (mirrors Go's `SetDir`).
    pub fn set_dir(&self, dir: impl Into<PathBuf>) {
        self.write_state().dir = dir.into();
    }

    /// Current configuration copy.
    pub fn config(&self) -> CertConfig {
        self.read_state().config.clone()
    }

    /// Current self-signed certificate directory.
    pub fn dir(&self) -> PathBuf {
        self.read_state().dir.clone()
    }

    /// Reload certificate material from the current configuration.
    pub fn reload(&self) {
        let (dir, config) = {
            let state = self.read_state();
            (state.dir.clone(), state.config.clone())
        };
        let result = load_material(&dir, &config);

        let mut state = self.write_state();
        match result {
            Ok(material) => {
                state.material = Some(material);
                state.load_error = None;
                state.loaded = true;
            }
            Err(error) => {
                state.material = None;
                state.load_error = Some(error);
                state.loaded = false;
            }
        }
    }

    /// Build a rustls server configuration for the loaded certificate.
    pub fn tls_config(&self, alpn: Vec<Vec<u8>>) -> Result<Arc<rustls::ServerConfig>, String> {
        let (cert_pem, key_pem) = {
            let state = self.read_state();
            if !state.loaded {
                return Err(match &state.load_error {
                    Some(error) => format!("服务端证书不可用: {error}"),
                    None => "服务端证书尚未载入".to_string(),
                });
            }
            let material = state
                .material
                .as_ref()
                .ok_or_else(|| "服务端证书尚未载入".to_string())?;
            (material.cert_pem.clone(), material.key_pem.clone())
        };

        let chain = parse_chain(&cert_pem).map_err(|error| format!("服务端证书不可用: {error}"))?;
        let key =
            parse_private_key(&key_pem).map_err(|error| format!("服务端证书不可用: {error}"))?;

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let mut config = rustls::ServerConfig::builder_with_provider(provider)
            .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
            .map_err(|error| format!("服务端证书不可用: {error}"))?
            .with_no_client_auth()
            .with_single_cert(chain, key)
            .map_err(|error| format!("服务端证书不可用: {error}"))?;
        config.alpn_protocols = alpn;
        Ok(Arc::new(config))
    }

    /// Read-only certificate summary for the UI.
    pub fn info(&self) -> CertInfo {
        let state = self.read_state();
        let mut info = CertInfo {
            source: state.config.source.clone(),
            ..Default::default()
        };

        let Some(material) = &state.material else {
            info.error = state
                .load_error
                .clone()
                .unwrap_or_else(|| "证书尚未载入".to_string());
            return info;
        };

        let leaf = &material.leaf;
        info.loaded = true;
        info.subject = leaf.subject.clone();
        info.issuer = leaf.issuer.clone();
        info.serial_number = leaf.serial_number.clone();
        info.not_before = leaf.not_before.clone();
        info.not_after = leaf.not_after.clone();
        info.dns_names = leaf.dns_names.clone();
        info.ip_addresses = leaf.ip_addresses.clone();
        info.days_remaining = days_remaining(leaf.not_after_unix, Utc::now().timestamp());
        info.fingerprint = leaf.fingerprint.clone();
        info.chain_length = leaf.chain_length;
        info.self_signed = leaf.self_signed;
        info
    }

    /// Lifecycle state of the current certificate.
    pub fn health(&self) -> CertHealth {
        let state = self.read_state();
        let source = state.config.source.as_str();
        let mut health = CertHealth {
            self_signed: source.is_empty() || source == CERT_SOURCE_SELF_SIGNED,
            ..Default::default()
        };

        let Some(material) = &state.material else {
            return health;
        };

        let now = Utc::now().timestamp();
        let leaf = &material.leaf;
        health.loaded = true;
        health.not_after = leaf.not_after_unix;
        health.days_remaining = days_remaining(leaf.not_after_unix, now);
        health.expired = leaf.not_after_unix <= now;
        health.not_yet_valid = now < leaf.not_before_unix;
        health.expires_soon = within_renewal_window(leaf.not_after_unix, now);
        health
    }

    /// Ensure a self-signed certificate exists; returns `true` when one was generated.
    pub fn ensure_self_signed(&self, config: CertConfig) -> Result<bool, String> {
        let mut config = config;
        normalize_cert_config(&mut config);

        let dir = self.dir();
        if dir.as_os_str().is_empty() {
            return Err("证书目录未配置".to_string());
        }
        let cert_path = dir.join(SELF_SIGNED_CERT_FILE);
        let key_path = dir.join(SELF_SIGNED_KEY_FILE);

        // Reuse only files we own: an imported PEM recorded under source=file must not be
        // mistaken for our self-signed material (Go's BUG-64).
        if cert_path.is_file() && key_path.is_file() && self.owned_by_self_signed() {
            self.configure(with_source(config, CERT_SOURCE_SELF_SIGNED));
            return Ok(false);
        }

        let generated = generate_self_signed(&config)?;
        write_private(&cert_path, generated.cert_pem.as_bytes())?;
        write_private(&key_path, generated.key_pem.as_bytes())?;

        self.configure(with_source(config, CERT_SOURCE_SELF_SIGNED));
        Ok(true)
    }

    /// Unconditionally issue a new self-signed certificate.
    pub fn regenerate_self_signed(&self, config: CertConfig) -> Result<(), String> {
        let mut config = config;
        normalize_cert_config(&mut config);

        let dir = self.dir();
        if dir.as_os_str().is_empty() {
            return Err("证书目录未配置".to_string());
        }

        let generated = generate_self_signed(&config)?;
        write_private(
            &dir.join(SELF_SIGNED_CERT_FILE),
            generated.cert_pem.as_bytes(),
        )?;
        write_private(
            &dir.join(SELF_SIGNED_KEY_FILE),
            generated.key_pem.as_bytes(),
        )?;

        self.configure(with_source(config, CERT_SOURCE_SELF_SIGNED));
        Ok(())
    }

    /// Validate and import a PEM certificate/key pair.
    pub fn import_pem(&self, cert_pem: &[u8], key_pem: &[u8]) -> Result<(), String> {
        // Parse, verify the pair and only then touch the directory: writing a mismatched pair
        // would surface as a TLS handshake failure on the next start, far from the user's action.
        parse_pair(cert_pem, key_pem)?;

        let dir = self.dir();
        if dir.as_os_str().is_empty() {
            return Err("证书目录未配置".to_string());
        }
        let cert_path = dir.join(IMPORTED_CERT_FILE);
        let key_path = dir.join(IMPORTED_KEY_FILE);

        write_private(&cert_path, cert_pem)?;
        write_private(&key_path, key_pem)?;

        let mut config = self.config();
        config.source = CERT_SOURCE_FILE.to_string();
        config.cert_file = cert_path.to_string_lossy().into_owned();
        config.key_file = key_path.to_string_lossy().into_owned();
        self.configure(config);
        Ok(())
    }

    /// Decode a PKCS#12 archive and import its leaf certificate and private key as PEM.
    ///
    /// Mirrors Go's `ImportPKCS12`, which also normalizes the archive into the imported PEM pair
    /// so later loads never depend on the original archive or its password again.
    pub fn import_pkcs12(&self, pfx: &[u8], password: &str) -> Result<(), String> {
        let (cert_pem, key_pem) = decode_pkcs12(pfx, password)?;
        self.import_pem(&cert_pem, &key_pem)
    }

    /// Paths of the certificate and private key currently in effect.
    pub fn current_paths(&self) -> (PathBuf, PathBuf) {
        let (dir, config) = {
            let state = self.read_state();
            (state.dir.clone(), state.config.clone())
        };
        match resolve_paths(&dir, &config) {
            Ok(paths) => (paths.cert, paths.key),
            Err(_) => (PathBuf::new(), PathBuf::new()),
        }
    }

    /// Report whether the on-disk fixed-name files belong to the self-signed source.
    fn owned_by_self_signed(&self) -> bool {
        let state = self.read_state();
        let source = state.config.source.as_str();
        if source.is_empty() || source == CERT_SOURCE_SELF_SIGNED {
            return true;
        }
        if source != CERT_SOURCE_FILE {
            return false;
        }
        let expected = state.dir.join(SELF_SIGNED_CERT_FILE);
        if !same_file_path(Path::new(&state.config.cert_file), &expected) {
            return false;
        }
        // Legacy versions wrote imported PEMs to server.crt too. Only trust the file name when
        // the loaded leaf really is self-signed.
        state
            .material
            .as_ref()
            .map(|material| material.leaf.self_signed)
            .unwrap_or(false)
    }

    fn read_state(&self) -> std::sync::RwLockReadGuard<'_, State> {
        self.inner
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn write_state(&self) -> std::sync::RwLockWriteGuard<'_, State> {
        self.inner
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

fn with_source(mut config: CertConfig, source: &str) -> CertConfig {
    config.source = source.to_string();
    config
}
