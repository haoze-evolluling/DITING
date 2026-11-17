//! Certificate material loading, parsing and private file writing.
//!
//! Split out of `manager.rs` to keep both files within the project's 600-line limit; it mirrors
//! the helpers at the bottom of Go's `cert_manager.go`.

use std::fs;
use std::io::{BufReader, Write};
use std::net::{Ipv4Addr, Ipv6Addr};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use chrono::{DateTime, SecondsFormat, Utc};
use diting_desktop_api::config::security::{
    CertConfig, CERT_SOURCE_PKCS12, CERT_SOURCE_SELF_SIGNED,
};
use rustls::pki_types::CertificateDer;
use rustls_pemfile::{certs, private_key};
use sha2::{Digest, Sha256};
use x509_cert::der::{Decode, Encode};
use x509_cert::ext::pkix::name::GeneralName;
use x509_cert::ext::pkix::SubjectAltName;
use x509_cert::Certificate as X509Certificate;

use super::{SELF_SIGNED_CERT_FILE, SELF_SIGNED_KEY_FILE};

/// PKCS#12 is intentionally unsupported: no decoder is part of this crate's dependency set and
/// adding one is out of scope. Both import and load report the same actionable message.
pub(crate) const PKCS12_UNSUPPORTED: &str = "暂不支持 PKCS#12 导入：请使用 PEM 格式";

/// Parsed view of the end-entity certificate.
#[derive(Debug, Clone)]
pub(crate) struct Leaf {
    pub subject: String,
    pub issuer: String,
    pub serial_number: String,
    pub not_before: String,
    pub not_after: String,
    pub not_before_unix: i64,
    pub not_after_unix: i64,
    pub dns_names: Vec<String>,
    pub ip_addresses: Vec<String>,
    pub chain_length: i64,
    pub self_signed: bool,
    pub fingerprint: String,
}

/// Validated PEM pair plus its summary.
#[derive(Debug, Clone)]
pub(crate) struct Material {
    pub cert_pem: Vec<u8>,
    pub key_pem: Vec<u8>,
    pub leaf: Leaf,
}

pub(crate) struct ResolvedPaths {
    pub cert: PathBuf,
    pub key: PathBuf,
}

/// Read the configured pair from disk and validate it.
pub(crate) fn load_material(dir: &Path, config: &CertConfig) -> Result<Material, String> {
    if config.source == CERT_SOURCE_PKCS12 {
        return Err(PKCS12_UNSUPPORTED.to_string());
    }

    let paths = resolve_paths(dir, config)?;
    let cert_pem = fs::read(&paths.cert).map_err(|error| format!("读取证书失败: {error}"))?;
    let key_pem = fs::read(&paths.key).map_err(|error| format!("读取私钥失败: {error}"))?;

    let chain = parse_pair(&cert_pem, &key_pem)?;
    let leaf = summarize(&chain)?;
    Ok(Material {
        cert_pem,
        key_pem,
        leaf,
    })
}

/// Derive the effective certificate/key paths from the configuration.
pub(crate) fn resolve_paths(dir: &Path, config: &CertConfig) -> Result<ResolvedPaths, String> {
    let source = config.source.as_str();
    if source.is_empty() || source == CERT_SOURCE_SELF_SIGNED {
        if dir.as_os_str().is_empty() {
            return Err("证书目录未配置".to_string());
        }
        return Ok(ResolvedPaths {
            cert: dir.join(SELF_SIGNED_CERT_FILE),
            key: dir.join(SELF_SIGNED_KEY_FILE),
        });
    }

    let cert = PathBuf::from(config.cert_file.trim());
    if cert.as_os_str().is_empty() {
        return Err("未指定证书文件路径".to_string());
    }
    if source == CERT_SOURCE_PKCS12 {
        return Ok(ResolvedPaths {
            cert: cert.clone(),
            key: cert,
        });
    }

    let key = PathBuf::from(config.key_file.trim());
    if key.as_os_str().is_empty() {
        return Err("未指定私钥文件路径".to_string());
    }
    Ok(ResolvedPaths { cert, key })
}

/// Parse and validate a PEM pair, returning the certificate chain.
pub(crate) fn parse_pair(
    cert_pem: &[u8],
    key_pem: &[u8],
) -> Result<Vec<CertificateDer<'static>>, String> {
    let chain = parse_chain(cert_pem)?;
    let key = parse_private_key(key_pem)?;

    // `CertifiedKey::from_der` loads the private key and verifies it matches the leaf's SPKI.
    let provider = rustls::crypto::ring::default_provider();
    let certified = rustls::sign::CertifiedKey::from_der(chain, key, &provider)
        .map_err(|error| format!("证书与私钥不匹配或格式无效: {error}"))?;
    Ok(certified.cert)
}

pub(crate) fn parse_chain(cert_pem: &[u8]) -> Result<Vec<CertificateDer<'static>>, String> {
    let chain = certs(&mut BufReader::new(cert_pem))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("解析证书链失败: {error}"))?;
    if chain.is_empty() {
        return Err("证书文件中没有可用的 CERTIFICATE 块".to_string());
    }
    Ok(chain)
}

pub(crate) fn parse_private_key(
    pem: &[u8],
) -> Result<rustls::pki_types::PrivateKeyDer<'static>, String> {
    private_key(&mut BufReader::new(pem))
        .map_err(|error| format!("解析私钥失败: {error}"))?
        .ok_or_else(|| "私钥文件中没有可用的 PRIVATE KEY 块".to_string())
}

fn summarize(chain: &[CertificateDer<'static>]) -> Result<Leaf, String> {
    let der = chain.first().ok_or_else(|| "证书链为空".to_string())?;
    let certificate = X509Certificate::from_der(der.as_ref())
        .map_err(|error| format!("解析证书链失败: {error}"))?;

    let tbs = &certificate.tbs_certificate;
    let not_before_unix = tbs.validity.not_before.to_unix_duration().as_secs() as i64;
    let not_after_unix = tbs.validity.not_after.to_unix_duration().as_secs() as i64;
    let (dns_names, ip_addresses) = subject_alt_names(&certificate);

    Ok(Leaf {
        subject: tbs.subject.to_string(),
        issuer: tbs.issuer.to_string(),
        serial_number: format_serial(tbs.serial_number.as_bytes()),
        not_before: rfc3339(not_before_unix),
        not_after: rfc3339(not_after_unix),
        not_before_unix,
        not_after_unix,
        dns_names,
        ip_addresses,
        chain_length: chain.len() as i64,
        self_signed: is_self_signed(&certificate),
        fingerprint: format_fingerprint(&Sha256::digest(der.as_ref())),
    })
}

fn subject_alt_names(certificate: &X509Certificate) -> (Vec<String>, Vec<String>) {
    let mut dns_names = Vec::new();
    let mut ip_addresses = Vec::new();

    let Some(extensions) = certificate.tbs_certificate.extensions.as_deref() else {
        return (dns_names, ip_addresses);
    };
    for extension in extensions {
        if extension.extn_id.to_string() != "2.5.29.17" {
            continue;
        }
        let Ok(san) = SubjectAltName::from_der(extension.extn_value.as_bytes()) else {
            continue;
        };
        for name in san.0 {
            match name {
                GeneralName::DnsName(name) => dns_names.push(name.as_str().to_string()),
                GeneralName::IpAddress(bytes) => {
                    if let Some(address) = format_ip(bytes.as_bytes()) {
                        ip_addresses.push(address);
                    }
                }
                _ => {}
            }
        }
    }

    (dns_names, ip_addresses)
}

fn format_ip(bytes: &[u8]) -> Option<String> {
    match bytes {
        [a, b, c, d] => Some(Ipv4Addr::new(*a, *b, *c, *d).to_string()),
        _ if bytes.len() == 16 => {
            let mut octets = [0u8; 16];
            octets.copy_from_slice(bytes);
            Some(Ipv6Addr::from(octets).to_string())
        }
        _ => None,
    }
}

/// Compare the raw issuer and subject TBS bytes, like Go's `isSelfSigned`.
fn is_self_signed(certificate: &X509Certificate) -> bool {
    match (
        certificate.tbs_certificate.issuer.to_der(),
        certificate.tbs_certificate.subject.to_der(),
    ) {
        (Ok(issuer), Ok(subject)) => issuer == subject,
        _ => false,
    }
}

fn format_serial(bytes: &[u8]) -> String {
    let hex: String = bytes.iter().map(|byte| format!("{byte:02X}")).collect();
    let trimmed = hex.trim_start_matches('0');
    if trimmed.is_empty() {
        "0".to_string()
    } else {
        trimmed.to_string()
    }
}

fn format_fingerprint(digest: &[u8]) -> String {
    digest
        .iter()
        .map(|byte| format!("{byte:02X}"))
        .collect::<Vec<_>>()
        .join(":")
}

fn rfc3339(seconds: i64) -> String {
    DateTime::<Utc>::from_timestamp(seconds, 0)
        .map(|time| time.to_rfc3339_opts(SecondsFormat::Secs, true))
        .unwrap_or_default()
}

/// Compare two paths ignoring relative-path noise and ASCII case differences (Go's
/// `sameFilePath`).
pub(crate) fn same_file_path(a: &Path, b: &Path) -> bool {
    if a.as_os_str().is_empty() || b.as_os_str().is_empty() {
        return false;
    }
    let normalize = |path: &Path| {
        let absolute = if path.is_absolute() {
            path.to_path_buf()
        } else {
            std::env::current_dir()
                .map(|cwd| cwd.join(path))
                .unwrap_or_else(|_| path.to_path_buf())
        };
        absolute
            .components()
            .collect::<PathBuf>()
            .to_string_lossy()
            .into_owned()
    };
    normalize(a).eq_ignore_ascii_case(&normalize(b))
}

/// Atomically write `data` to `path` with owner-only permissions.
pub(crate) fn write_private(path: &Path, data: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent).map_err(|error| format!("创建证书目录失败: {error}"))?;
    set_dir_mode_private(parent);

    let temporary = temp_path(path);
    {
        let mut file = fs::File::create(&temporary)
            .map_err(|error| format!("写入 {} 失败: {error}", file_name(path)))?;
        file.write_all(data)
            .map_err(|error| format!("写入 {} 失败: {error}", file_name(path)))?;
        let _ = file.sync_all();
    }
    set_file_mode_private(&temporary);

    if let Err(error) = fs::rename(&temporary, path) {
        let _ = fs::remove_file(&temporary);
        return Err(format!("写入 {} 失败: {error}", file_name(path)));
    }
    // Re-apply after the rename: an existing destination replaced by `rename` keeps the new
    // file's mode, but being explicit also covers platforms/paths where it does not.
    set_file_mode_private(path);
    Ok(())
}

fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned())
}

fn temp_path(path: &Path) -> PathBuf {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let name = file_name(path);
    path.with_file_name(format!(".{name}.tmp-{}-{counter}", std::process::id()))
}

#[cfg(unix)]
fn set_dir_mode_private(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o700));
}

#[cfg(not(unix))]
fn set_dir_mode_private(_path: &Path) {
    // Windows has no POSIX mode. Tightening the ACL needs the platform crate, which is not a
    // dependency of this crate yet; the directory still inherits the data directory's ACL.
}

#[cfg(unix)]
fn set_file_mode_private(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
}

#[cfg(not(unix))]
fn set_file_mode_private(_path: &Path) {
    // See `set_dir_mode_private`: no ACL hardening on Windows in this crate.
}
