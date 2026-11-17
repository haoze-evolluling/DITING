//! Certificate manager tests.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use diting_desktop_api::config::security::{CertConfig, CERT_SOURCE_FILE, CERT_SOURCE_SELF_SIGNED};

use super::generate::generate_self_signed;
use super::manager::CertManager;
use super::{IMPORTED_CERT_FILE, IMPORTED_KEY_FILE, SELF_SIGNED_CERT_FILE, SELF_SIGNED_KEY_FILE};

static NEXT_ID: AtomicU64 = AtomicU64::new(0);

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(name: &str) -> Self {
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("diting-cert-{name}-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("create temp dir");
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

fn config() -> CertConfig {
    CertConfig {
        source: CERT_SOURCE_SELF_SIGNED.to_string(),
        key_type: "ecdsa".to_string(),
        common_name: "dns.lan".to_string(),
        dns_names: vec!["dns.lan".to_string()],
        ip_addresses: vec!["127.0.0.1".to_string()],
        valid_days: 825,
        ..CertConfig::default()
    }
}

fn pair(config: &CertConfig) -> (Vec<u8>, Vec<u8>) {
    let generated = generate_self_signed(config).expect("generate pair");
    (
        generated.cert_pem.into_bytes(),
        generated.key_pem.into_bytes(),
    )
}

fn assert_uppercase_fingerprint(fingerprint: &str) {
    let parts: Vec<&str> = fingerprint.split(':').collect();
    assert_eq!(parts.len(), 32, "{fingerprint}");
    for part in parts {
        assert_eq!(part.len(), 2, "{fingerprint}");
        assert!(
            part.chars()
                .all(|character| character.is_ascii_hexdigit() && !character.is_ascii_lowercase()),
            "{fingerprint}"
        );
    }
}

#[test]
fn ensure_loads_reuses_and_regenerates() {
    let temp = TempDir::new("ensure");
    let manager = CertManager::new(temp.path(), config());

    // Nothing on disk yet: the manager is not loaded.
    assert!(!manager.info().loaded);
    assert!(!manager.info().error.is_empty());

    assert!(manager.ensure_self_signed(config()).expect("generate"));
    let cert_path = temp.path().join(SELF_SIGNED_CERT_FILE);
    let key_path = temp.path().join(SELF_SIGNED_KEY_FILE);
    assert!(cert_path.is_file());
    assert!(key_path.is_file());

    let info = manager.info();
    assert!(info.loaded);
    assert!(info.self_signed);
    assert_eq!(info.source, CERT_SOURCE_SELF_SIGNED);
    assert_eq!(info.dns_names, vec!["dns.lan"]);
    assert_eq!(info.ip_addresses, vec!["127.0.0.1"]);
    assert_eq!(info.chain_length, 1);
    assert!(info.days_remaining >= 800, "{}", info.days_remaining);
    assert!(info.not_before.ends_with('Z'), "{}", info.not_before);
    assert!(info.not_after.ends_with('Z'), "{}", info.not_after);
    assert!(!info.serial_number.is_empty());
    assert!(!info.serial_number.chars().any(|c| c.is_ascii_lowercase()));
    assert_uppercase_fingerprint(&info.fingerprint);
    assert_eq!(info.error, "");

    let health = manager.health();
    assert!(health.loaded);
    assert!(health.self_signed);
    assert!(!health.expired);
    assert!(!health.not_yet_valid);
    assert!(!health.expires_soon);
    assert!(health.days_remaining >= 800);
    assert!(health.not_after > 0);
    assert!(!health.needs_renewal());

    let first_cert = fs::read(&cert_path).unwrap();
    assert!(!manager.ensure_self_signed(config()).expect("reuse"));
    assert_eq!(fs::read(&cert_path).unwrap(), first_cert);

    manager
        .regenerate_self_signed(config())
        .expect("regenerate");
    let second_cert = fs::read(&cert_path).unwrap();
    assert_ne!(second_cert, first_cert);
    assert!(manager.info().loaded);
    assert!(manager.info().self_signed);
}

#[test]
fn tls_config_requires_and_uses_loaded_material() {
    let temp = TempDir::new("tls");
    let manager = CertManager::new(temp.path(), config());

    let error = manager.tls_config(Vec::new()).expect_err("not loaded");
    assert!(error.contains("服务端证书"), "{error}");

    manager.ensure_self_signed(config()).unwrap();
    let tls = manager
        .tls_config(vec![b"dot".to_vec(), b"h2".to_vec()])
        .expect("tls config");
    assert_eq!(tls.alpn_protocols, vec![b"dot".to_vec(), b"h2".to_vec()]);
}

#[test]
fn import_validates_pair_before_writing() {
    let temp = TempDir::new("import-invalid");
    let manager = CertManager::new(temp.path(), config());

    let (cert_a, _) = pair(&config());
    let mut other = config();
    other.common_name = "other.lan".to_string();
    other.dns_names = vec!["other.lan".to_string()];
    let (_, key_b) = pair(&other);

    let error = manager
        .import_pem(&cert_a, &key_b)
        .expect_err("mismatched pair");
    assert!(
        error.contains("不匹配") || error.contains("格式无效"),
        "{error}"
    );
    assert!(!temp.path().join(IMPORTED_CERT_FILE).exists());
    assert!(!temp.path().join(IMPORTED_KEY_FILE).exists());
    assert!(!manager.info().loaded);
}

#[test]
fn import_pem_switches_to_file_source() {
    let temp = TempDir::new("import-valid");
    let manager = CertManager::new(temp.path(), config());
    let (cert, key) = pair(&config());

    manager.import_pem(&cert, &key).expect("import");

    let cert_path = temp.path().join(IMPORTED_CERT_FILE);
    let key_path = temp.path().join(IMPORTED_KEY_FILE);
    assert_eq!(fs::read(&cert_path).unwrap(), cert);
    assert_eq!(fs::read(&key_path).unwrap(), key);

    let info = manager.info();
    assert!(info.loaded);
    assert_eq!(info.source, CERT_SOURCE_FILE);
    assert_eq!(manager.current_paths(), (cert_path, key_path));
    assert_eq!(manager.config().source, CERT_SOURCE_FILE);
}

#[test]
fn import_pkcs12_reports_the_gap() {
    let temp = TempDir::new("pkcs12");
    let manager = CertManager::new(temp.path(), config());
    let error = manager
        .import_pkcs12(&[], "secret")
        .expect_err("unsupported");
    assert!(error.contains("PKCS#12"), "{error}");
    assert!(error.contains("PEM"), "{error}");
}

#[test]
fn file_source_loads_explicit_paths() {
    let temp = TempDir::new("file-source");
    let (cert, key) = pair(&config());
    let cert_path = temp.path().join("external.crt");
    let key_path = temp.path().join("external.key");
    fs::write(&cert_path, cert).unwrap();
    fs::write(&key_path, key).unwrap();

    let mut config = config();
    config.source = CERT_SOURCE_FILE.to_string();
    config.cert_file = cert_path.to_string_lossy().into_owned();
    config.key_file = key_path.to_string_lossy().into_owned();

    let manager = CertManager::new(temp.path(), config);
    let info = manager.info();
    assert!(info.loaded);
    assert_eq!(info.source, CERT_SOURCE_FILE);
    assert!(info.self_signed);
    assert_eq!(manager.current_paths(), (cert_path, key_path));
    assert!(!manager.health().needs_renewal());
}

#[test]
fn legacy_self_signed_named_files_are_owned_and_reused() {
    let temp = TempDir::new("legacy-owned");
    CertManager::new(temp.path(), config())
        .ensure_self_signed(config())
        .unwrap();

    let mut legacy = config();
    legacy.source = CERT_SOURCE_FILE.to_string();
    legacy.cert_file = temp
        .path()
        .join(SELF_SIGNED_CERT_FILE)
        .to_string_lossy()
        .into_owned();
    legacy.key_file = temp
        .path()
        .join(SELF_SIGNED_KEY_FILE)
        .to_string_lossy()
        .into_owned();

    let manager = CertManager::new(temp.path(), legacy.clone());
    assert!(manager.info().loaded);
    let before = fs::read(temp.path().join(SELF_SIGNED_CERT_FILE)).unwrap();

    assert!(!manager.ensure_self_signed(legacy).expect("reuse legacy"));
    assert_eq!(manager.config().source, CERT_SOURCE_SELF_SIGNED);
    assert_eq!(
        fs::read(temp.path().join(SELF_SIGNED_CERT_FILE)).unwrap(),
        before
    );
}

#[test]
fn imported_files_are_not_reused_as_self_signed() {
    let temp = TempDir::new("imported-not-owned");
    let manager = CertManager::new(temp.path(), config());
    let (cert, key) = pair(&config());
    manager.import_pem(&cert, &key).expect("import");
    let imported_cert = temp.path().join(IMPORTED_CERT_FILE);
    let before = fs::read(&imported_cert).unwrap();

    // source=file now points at imported.crt, so the fixed-name pair must be generated anew.
    assert!(manager.ensure_self_signed(config()).expect("generate"));
    assert!(temp.path().join(SELF_SIGNED_CERT_FILE).is_file());
    assert_eq!(fs::read(imported_cert).unwrap(), before);
    assert_eq!(manager.config().source, CERT_SOURCE_SELF_SIGNED);
}

#[test]
fn expired_certificate_reports_negative_remaining_days() {
    use rcgen::{
        date_time_ymd, BasicConstraints, CertificateParams, DistinguishedName, DnType, IsCa,
        KeyPair, PKCS_ECDSA_P256_SHA256,
    };

    let temp = TempDir::new("expired");
    let key = KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256).unwrap();
    let mut params = CertificateParams::default();
    let mut name = DistinguishedName::new();
    name.push(DnType::CommonName, "expired.lan");
    params.distinguished_name = name;
    params.not_before = date_time_ymd(2020, 1, 1);
    params.not_after = date_time_ymd(2020, 2, 1);
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    let certificate = params.self_signed(&key).unwrap();

    fs::write(temp.path().join(SELF_SIGNED_CERT_FILE), certificate.pem()).unwrap();
    fs::write(temp.path().join(SELF_SIGNED_KEY_FILE), key.serialize_pem()).unwrap();

    let manager = CertManager::new(temp.path(), config());
    let health = manager.health();
    assert!(health.loaded);
    assert!(health.self_signed);
    assert!(health.expired);
    assert!(health.days_remaining < 0, "{}", health.days_remaining);
    assert!(!health.expires_soon);
    assert!(health.needs_renewal());
    assert!(manager.info().days_remaining < 0);
}

#[test]
fn set_dir_changes_the_self_signed_location() {
    let temp = TempDir::new("set-dir");
    let other = TempDir::new("set-dir-other");
    let manager = CertManager::new(temp.path(), config());
    manager.set_dir(other.path());
    assert_eq!(manager.dir(), other.path());
}

#[cfg(unix)]
#[test]
fn certificate_directory_and_files_are_private() {
    use std::os::unix::fs::PermissionsExt;

    let temp = TempDir::new("modes");
    let manager = CertManager::new(temp.path(), config());
    manager.ensure_self_signed(config()).unwrap();

    let dir_mode = fs::metadata(temp.path()).unwrap().permissions().mode() & 0o777;
    assert_eq!(dir_mode, 0o700);
    for name in [SELF_SIGNED_CERT_FILE, SELF_SIGNED_KEY_FILE] {
        let mode = fs::metadata(temp.path().join(name))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600, "{name}");
    }
}
