//! The upstream trust store the encrypted transports verify against.
//!
//! This is `upstreamRootPool()` from `mitm_trust.go`, which the Go resolver's DoH/DoT/DoQ clients
//! inherited through `tls.Config`'s nil `RootCAs`: the platform pool plus the two bundled ISRG
//! roots. On Android the platform pool is a directory of hashed PEM files and Go's `crypto/x509`
//! reads it from disk, so nothing here goes through JNI and user-installed CAs are *not* trusted —
//! the behaviour the migration has to keep.
//!
//! Android 14 moved the live system store into the Conscrypt APEX, so both directories are read;
//! that is a superset of the Go list and cannot widen trust beyond what the platform itself trusts.
//! `rustls-platform-verifier` is not used: it needs a `JavaVM`, follows the app's
//! `NetworkSecurityConfig` (so it starts trusting user CAs) and would change verification results
//! relative to the Go build.
//!
//! The two ISRG PEM files are the production copy. Stage 0's spike keeps its own frozen snapshot
//! because `diting-corpus` pins those bytes; stage 4 will collapse the spike into this module.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use rustls::crypto::CryptoProvider;
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::PrivateKeyDer;
use rustls::{ClientConfig, RootCertStore};

/// The ISRG Root X1 PEM, byte-identical to `isrgRootX1PEM` in `mitm_trust.go`.
pub const ISRG_ROOT_X1_PEM: &str = include_str!("res/isrg-root-x1.pem");
/// The ISRG Root X2 PEM, byte-identical to `isrgRootX2PEM` in `mitm_trust.go`.
pub const ISRG_ROOT_X2_PEM: &str = include_str!("res/isrg-root-x2.pem");
/// The bundled roots, in the order the Go code appended them.
pub const BUNDLED_ROOTS: [&str; 2] = [ISRG_ROOT_X1_PEM, ISRG_ROOT_X2_PEM];

/// Where Android keeps the system CA store, oldest first.
pub const ANDROID_CERT_DIRECTORIES: [&str; 2] = [
    "/system/etc/security/cacerts",
    "/apex/com.android.conscrypt/cacerts",
];

/// `encryptedClientALPN`: the DoH ALPN list of `http.Transport` (`h2` first, `http/1.1` second).
pub const DOH_ALPN: [&[u8]; 2] = [b"h2", b"http/1.1"];
/// The DoT endpoint is a raw TLS stream: `tls.Config` had no `NextProtos`.
pub const DOT_ALPN: [&[u8]; 0] = [];
/// `NextProtos: []string{"doq"}`.
pub const DOQ_ALPN: [&[u8]; 1] = [b"doq"];

/// What the platform read produced, for the log line Go printed (`bundled roots added=%d`).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RootStoreReport {
    /// Directories that existed and were read.
    pub directories: usize,
    /// Files read (many are skipped: Android ships 150+ named hashes per directory).
    pub files: usize,
    /// Certificates the directories contributed.
    pub system_certs: usize,
    /// Bundled roots the pool accepted.
    pub bundled_certs: usize,
}

/// The trust store every encrypted upstream connection verifies against.
///
/// The store is immutable once built, so one instance is shared by the whole engine (and by
/// `rustls`'s `ServerName` verification inside each handshake).
pub struct UpstreamTrust {
    roots: Arc<RootCertStore>,
    provider: Arc<CryptoProvider>,
    report: RootStoreReport,
}

impl UpstreamTrust {
    /// The platform pool plus the bundled ISRG roots, i.e. what Go's `x509.SystemCertPool()`
    /// produced on a device. A host without those directories ends up with the bundled roots only,
    /// which is the same degradation an unreadable platform pool caused.
    pub fn platform() -> Self {
        let mut roots = RootCertStore::empty();
        let mut report = RootStoreReport::default();
        for directory in ANDROID_CERT_DIRECTORIES {
            let (files, certs) = load_directory(&mut roots, Path::new(directory));
            if files > 0 {
                report.directories += 1;
                report.files += files;
                report.system_certs += certs;
            }
        }
        report.bundled_certs = add_pem_roots(&mut roots, &BUNDLED_ROOTS);
        Self::build(roots, report)
    }

    /// A store from an explicit root set: the test PKI, and stage 4's CA-inspection path.
    pub fn from_roots(roots: RootCertStore) -> Self {
        Self::build(roots, RootStoreReport::default())
    }

    fn build(roots: RootCertStore, report: RootStoreReport) -> Self {
        Self {
            roots: Arc::new(roots),
            provider: Arc::new(rustls::crypto::ring::default_provider()),
            report,
        }
    }

    pub fn report(&self) -> RootStoreReport {
        self.report
    }

    pub fn roots(&self) -> &RootCertStore {
        &self.roots
    }

    /// The crypto provider every TLS config in the engine is built from (`ring`, never `aws-lc-rs`:
    /// one cross-compilation story for Android, already proven by the MITM spike).
    pub fn provider(&self) -> Arc<CryptoProvider> {
        Arc::clone(&self.provider)
    }

    /// A client config with the given ALPN list.
    ///
    /// `tls12` and `tls13` are both offered, like Go's zero-value `tls.Config` (the DoQ caller
    /// narrows it to TLS 1.3 itself, as `quic-go` requires). Resumption keeps Go's 64-entry DoT
    /// session cache (`dotSessionCache`).
    pub fn client_config(&self, alpn: &[&[u8]]) -> Arc<ClientConfig> {
        let mut config = ClientConfig::builder_with_provider(Arc::clone(&self.provider))
            .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
            .expect("the ring provider supports TLS 1.2 and 1.3")
            .with_root_certificates((*self.roots).clone())
            .with_no_client_auth();
        config.alpn_protocols = alpn.iter().map(|protocol| protocol.to_vec()).collect();
        Arc::new(config)
    }

    /// The DoQ client config: TLS 1.3 only, `doq` ALPN.
    pub fn quic_client_config(&self) -> Arc<ClientConfig> {
        let mut config = ClientConfig::builder_with_provider(Arc::clone(&self.provider))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .expect("the ring provider supports TLS 1.3")
            .with_root_certificates((*self.roots).clone())
            .with_no_client_auth();
        config.alpn_protocols = DOQ_ALPN.iter().map(|protocol| protocol.to_vec()).collect();
        Arc::new(config)
    }
}

impl Default for UpstreamTrust {
    fn default() -> Self {
        Self::platform()
    }
}

/// `AppendCertsFromPEM` for every PEM in `pems`, returning how many were accepted.
pub fn add_pem_roots(roots: &mut RootCertStore, pems: &[&str]) -> usize {
    let mut added = 0;
    for pem in pems {
        let mut reader = std::io::BufReader::new(pem.as_bytes());
        let certs = rustls_pemfile::certs(&mut reader).filter_map(Result::ok);
        let (accepted, _) = roots.add_parsable_certificates(certs);
        added += accepted;
    }
    added
}

/// Reads every file in `directory` as PEM and adds whatever parses.
///
/// Returns `(files read, certificates added)`. A missing or unreadable directory is `(0, 0)`: on a
/// host, or on an Android release without the APEX directory, the path simply does not exist.
pub fn load_directory(roots: &mut RootCertStore, directory: &Path) -> (usize, usize) {
    let Ok(entries) = fs::read_dir(directory) else {
        return (0, 0);
    };
    let mut files = 0;
    let mut certs = 0;
    // Sorted so two runs against the same directory build the same pool.
    let mut paths: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_file())
        .collect();
    paths.sort();
    for path in paths {
        let Ok(bytes) = fs::read(&path) else {
            continue;
        };
        files += 1;
        let mut reader = std::io::BufReader::new(bytes.as_slice());
        let parsed = rustls_pemfile::certs(&mut reader).filter_map(Result::ok);
        let (accepted, _) = roots.add_parsable_certificates(parsed);
        certs += accepted;
    }
    (files, certs)
}

/// One certificate plus its key, parsed from PEM for the loopback servers of the tests.
///
/// It lives here (and not in the test file) because the DoT/DoH/DoQ servers all need the same two
/// lines, and `rustls-pemfile` is already a dependency of the engine.
pub fn certificate_from_pem(
    chain_pem: &str,
    key_pem: &str,
) -> Result<
    (
        Vec<rustls::pki_types::CertificateDer<'static>>,
        PrivateKeyDer<'static>,
    ),
    String,
> {
    let chain = rustls_pemfile::certs(&mut std::io::BufReader::new(chain_pem.as_bytes()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("parse test certificate: {error}"))?;
    let key = PrivateKeyDer::from_pem_slice(key_pem.as_bytes())
        .map_err(|error| format!("parse test key: {error}"))?;
    Ok((chain, key))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_roots_parse() {
        let mut roots = RootCertStore::empty();
        assert_eq!(add_pem_roots(&mut roots, &BUNDLED_ROOTS), 2);
        assert_eq!(roots.len(), 2);
    }

    #[test]
    fn the_platform_store_always_carries_the_bundled_roots() {
        let trust = UpstreamTrust::platform();
        assert_eq!(trust.report().bundled_certs, 2);
        assert!(trust.roots().len() >= 2);
    }

    #[test]
    fn a_directory_of_pem_files_becomes_a_pool() {
        let ca = diting_cert_core::ca::CertAuthority::generate(now()).expect("mint a CA");
        let directory = std::env::temp_dir().join(format!(
            "diting-engine-trust-{}-{}",
            std::process::id(),
            now()
        ));
        fs::create_dir_all(&directory).expect("create the scratch directory");
        // Android names its files by subject hash; the loader must not care about the name.
        fs::write(directory.join("9aae4af1.0"), ca.authority.ca_pem()).expect("write the cert");
        fs::write(directory.join("not-a-cert.pem"), "garbage\n").expect("write junk");

        let mut roots = RootCertStore::empty();
        let (files, certs) = load_directory(&mut roots, &directory);
        assert_eq!((files, certs), (2, 1));
        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn the_three_client_configs_differ_only_in_alpn_and_versions() {
        let trust = UpstreamTrust::platform();
        assert_eq!(
            trust.client_config(&DOH_ALPN).alpn_protocols,
            vec![b"h2".to_vec(), b"http/1.1".to_vec()]
        );
        assert!(trust.client_config(&DOT_ALPN).alpn_protocols.is_empty());
        assert_eq!(
            trust.quic_client_config().alpn_protocols,
            vec![b"doq".to_vec()]
        );
    }

    fn now() -> i64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_secs() as i64)
            .unwrap_or(0)
    }
}
