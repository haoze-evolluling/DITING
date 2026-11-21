use std::fs;
use std::path::{Path, PathBuf};

use der::Decode;
use rustls::RootCertStore;
use x509_cert::ext::pkix::certpolicy::CertificatePolicies;
use x509_cert::Certificate;

pub const ISRG_ROOT_X1_PEM: &str = include_str!("res/isrg-root-x1.pem");
pub const ISRG_ROOT_X2_PEM: &str = include_str!("res/isrg-root-x2.pem");

pub const BUNDLED_ROOTS: [&str; 2] = [ISRG_ROOT_X1_PEM, ISRG_ROOT_X2_PEM];

pub const ANDROID_CERT_DIRECTORIES: [&str; 2] = [
    "/system/etc/security/cacerts",
    "/apex/com.android.conscrypt/cacerts",
];

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RootStoreReport {
    pub directories: usize,
    pub files: usize,
    pub system_certs: usize,
    pub bundled_certs: usize,
}

pub fn upstream_root_store() -> (RootCertStore, RootStoreReport) {
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
    (roots, report)
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

pub fn policy_identifiers(cert_der: &[u8]) -> Vec<String> {
    let Ok(cert) = Certificate::from_der(cert_der) else {
        return Vec::new();
    };
    let Some(extensions) = cert.tbs_certificate().extensions() else {
        return Vec::new();
    };
    let mut identifiers = Vec::new();
    for extension in extensions {
        if extension.extn_id != const_oid::db::rfc5912::ID_CE_CERTIFICATE_POLICIES {
            continue;
        }
        let Ok(policies) = CertificatePolicies::from_der(extension.extn_value.as_bytes()) else {
            continue;
        };
        for policy in policies.0 {
            identifiers.push(policy.policy_identifier.to_string());
        }
    }
    identifiers
}

pub fn is_extended_validation(cert_der: &[u8]) -> bool {
    let identifiers = policy_identifiers(cert_der);
    let borrowed: Vec<&str> = identifiers.iter().map(String::as_str).collect();
    diting_cert_core::ev::is_extended_validation(&borrowed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rustls::client::danger::ServerCertVerifier;
    use rustls::pki_types::CertificateDer;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "diting-trust-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|elapsed| elapsed.as_nanos())
                .unwrap_or(0)
        ));
        fs::create_dir_all(&dir).expect("create the scratch directory");
        dir
    }

    #[test]
    fn bundled_roots_parse() {
        let mut roots = RootCertStore::empty();
        assert_eq!(add_pem_roots(&mut roots, &BUNDLED_ROOTS), 2);
        assert_eq!(roots.len(), 2);
    }

    #[test]
    fn a_directory_of_pem_files_becomes_a_pool() {
        let ca = diting_cert_core::ca::CertAuthority::generate(now()).expect("mint a CA");
        let dir = temp_dir("dir");
        fs::write(dir.join("9aae4af1.0"), ca.authority.ca_pem()).expect("write the certificate");
        fs::write(dir.join("not-a-cert.pem"), "garbage\n").expect("write junk");
        fs::create_dir_all(dir.join("nested")).expect("create a nested directory");

        let mut roots = RootCertStore::empty();
        let (files, certs) = load_directory(&mut roots, &dir);
        assert_eq!(files, 2, "junk files are read, then dropped");
        assert_eq!(certs, 1);
        assert_eq!(roots.len(), 1);

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn a_missing_directory_is_not_an_error() {
        let mut roots = RootCertStore::empty();
        assert_eq!(
            load_directory(&mut roots, Path::new("/nonexistent/diting/cacerts")),
            (0, 0)
        );
        assert!(roots.is_empty());
    }

    #[test]
    fn only_a_loaded_root_verifies_an_upstream_chain() {
        let trusted = diting_cert_core::ca::CertAuthority::generate(now()).expect("mint a CA");
        let untrusted = diting_cert_core::ca::CertAuthority::generate(now()).expect("mint a CA");

        let mut roots = RootCertStore::empty();
        assert_eq!(add_pem_roots(&mut roots, &[trusted.authority.ca_pem()]), 1);

        let leaf = trusted
            .authority
            .issue("upstream.test", now())
            .expect("mint a leaf");
        let chain = pem_certs(&leaf.chain_pem);
        let verifier = rustls::client::WebPkiServerVerifier::builder(Arc::new(roots))
            .build()
            .expect("build a verifier");
        let end_entity = chain[0].clone();
        let intermediates = chain[1..].to_vec();
        let server_name = rustls::pki_types::ServerName::try_from("upstream.test").unwrap();
        assert!(
            verifier
                .verify_server_cert(&end_entity, &intermediates, &server_name, &[], unix_now(),)
                .is_ok(),
            "a leaf signed by the loaded root must verify"
        );

        let foreign = untrusted
            .authority
            .issue("upstream.test", now())
            .expect("mint a leaf");
        let foreign_chain = pem_certs(&foreign.chain_pem);
        assert!(
            verifier
                .verify_server_cert(
                    &foreign_chain[0],
                    &foreign_chain[1..],
                    &server_name,
                    &[],
                    unix_now(),
                )
                .is_err(),
            "a leaf from an unknown CA must never verify"
        );
    }

    #[test]
    fn extended_validation_reads_policy_oids_from_der() {
        let ca = diting_cert_core::ca::CertAuthority::generate(now()).expect("mint a CA");
        let leaf = ca.authority.issue("bank.test", now()).expect("mint a leaf");
        let plain = pem_certs(&leaf.chain_pem);
        assert!(
            !is_extended_validation(plain[0].as_ref()),
            "a minted leaf carries no CA/Browser Forum policy"
        );
        assert!(policy_identifiers(plain[0].as_ref()).is_empty());
        assert!(!is_extended_validation(b"not a certificate"));
    }

    fn pem_certs(pem: &str) -> Vec<CertificateDer<'static>> {
        rustls_pemfile::certs(&mut std::io::BufReader::new(pem.as_bytes()))
            .filter_map(Result::ok)
            .collect()
    }

    fn now() -> i64 {
        crate::now_unix()
    }

    fn unix_now() -> rustls::pki_types::UnixTime {
        rustls::pki_types::UnixTime::since_unix_epoch(std::time::Duration::from_secs(now() as u64))
    }

    use std::sync::Arc;
}
