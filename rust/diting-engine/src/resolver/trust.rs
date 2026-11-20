use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use rustls::crypto::CryptoProvider;
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::PrivateKeyDer;
use rustls::{ClientConfig, RootCertStore};

pub const ISRG_ROOT_X1_PEM: &str = include_str!("res/isrg-root-x1.pem");
pub const ISRG_ROOT_X2_PEM: &str = include_str!("res/isrg-root-x2.pem");
pub const BUNDLED_ROOTS: [&str; 2] = [ISRG_ROOT_X1_PEM, ISRG_ROOT_X2_PEM];

pub const ANDROID_CERT_DIRECTORIES: [&str; 2] = [
    "/system/etc/security/cacerts",
    "/apex/com.android.conscrypt/cacerts",
];

pub const DOH_ALPN: [&[u8]; 2] = [b"h2", b"http/1.1"];
pub const DOT_ALPN: [&[u8]; 0] = [];
pub const DOQ_ALPN: [&[u8]; 1] = [b"doq"];
pub const H3_ALPN: [&[u8]; 1] = [b"h3"];

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RootStoreReport {
    pub directories: usize,
    pub files: usize,
    pub system_certs: usize,
    pub bundled_certs: usize,
}

pub struct UpstreamTrust {
    roots: Arc<RootCertStore>,
    provider: Arc<CryptoProvider>,
    pins: Arc<crate::resolver::pin::PinStore>,
    report: RootStoreReport,
}

impl UpstreamTrust {
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

    pub fn from_roots(roots: RootCertStore) -> Self {
        Self::build(roots, RootStoreReport::default())
    }

    fn build(roots: RootCertStore, report: RootStoreReport) -> Self {
        Self {
            roots: Arc::new(roots),
            provider: Arc::new(rustls::crypto::ring::default_provider()),
            pins: Arc::new(crate::resolver::pin::PinStore::default()),
            report,
        }
    }

    pub fn with_pins<I, H, P>(&self, pairs: I) -> Result<Self, String>
    where
        I: IntoIterator<Item = (H, P)>,
        H: AsRef<str>,
        P: AsRef<str>,
    {
        Ok(Self {
            roots: Arc::clone(&self.roots),
            provider: Arc::clone(&self.provider),
            pins: Arc::new(crate::resolver::pin::PinStore::from_pairs(pairs)?),
            report: self.report,
        })
    }

    pub fn with_pin_hashes<I, H>(&self, pairs: I) -> Self
    where
        I: IntoIterator<Item = (H, [u8; 32])>,
        H: AsRef<str>,
    {
        let mut store = crate::resolver::pin::PinStore::default();
        for (host, pin) in pairs {
            store.insert_hash(host.as_ref(), pin);
        }
        Self {
            roots: Arc::clone(&self.roots),
            provider: Arc::clone(&self.provider),
            pins: Arc::new(store),
            report: self.report,
        }
    }

    pub fn has_pins(&self) -> bool {
        !self.pins.is_empty()
    }

    pub fn report(&self) -> RootStoreReport {
        self.report
    }

    pub fn roots(&self) -> &RootCertStore {
        &self.roots
    }

    pub fn provider(&self) -> Arc<CryptoProvider> {
        Arc::clone(&self.provider)
    }

    pub fn client_config(&self, alpn: &[&[u8]]) -> Arc<ClientConfig> {
        crate::resolver::pin::client_config(
            &self.roots,
            Arc::clone(&self.provider),
            Arc::clone(&self.pins),
            alpn,
            false,
        )
    }

    pub fn quic_client_config(&self) -> Arc<ClientConfig> {
        crate::resolver::pin::client_config(
            &self.roots,
            Arc::clone(&self.provider),
            Arc::clone(&self.pins),
            &DOQ_ALPN,
            true,
        )
    }

    pub fn h3_client_config(&self) -> Arc<ClientConfig> {
        crate::resolver::pin::client_config(
            &self.roots,
            Arc::clone(&self.provider),
            Arc::clone(&self.pins),
            &H3_ALPN,
            true,
        )
    }
}

impl Default for UpstreamTrust {
    fn default() -> Self {
        Self::platform()
    }
}

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

pub fn load_directory(roots: &mut RootCertStore, directory: &Path) -> (usize, usize) {
    let Ok(entries) = fs::read_dir(directory) else {
        return (0, 0);
    };
    let mut files = 0;
    let mut certs = 0;
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
