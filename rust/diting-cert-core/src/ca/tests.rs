//! CA generation, persisted-root validation and leaf minting, pinned field by field against the
//! profile `crypto/x509` produced.

use const_oid::db::rfc5280::ID_CE_SUBJECT_KEY_IDENTIFIER;
use der::Decode;
use p256::pkcs8::EncodePrivateKey;
use x509_cert::ext::pkix::name::GeneralName;
use x509_cert::ext::pkix::{
    AuthorityKeyIdentifier, BasicConstraints, ExtendedKeyUsage, KeyUsage, SubjectAltName,
};
use x509_cert::{der::referenced::OwnedToRef, Certificate};

use super::*;
use crate::ca::dns_names as ca_dns_names;

/// A fixed instant: 2026-11-07T12:00:00Z.
const NOW: i64 = 1_794_052_800;

fn certificate(pem_text: &str) -> Certificate {
    Certificate::from_der(&pem::decode(pem_text).expect("PEM block").der).expect("DER certificate")
}

fn extension<'a, T>(cert: &'a Certificate) -> Option<T>
where
    T: Decode<'a> + AssociatedOid,
{
    let extensions = cert.tbs_certificate.extensions.as_ref()?;
    extensions
        .iter()
        .find(|extension| extension.extn_id == T::OID)
        .and_then(|extension| T::from_der(extension.extn_value.as_bytes()).ok())
}

fn san_names(cert: &Certificate) -> Vec<String> {
    let san: Option<SubjectAltName> = extension(cert);
    san.map(|san| {
        san.0
            .iter()
            .filter_map(|name| match name {
                GeneralName::DnsName(name) => {
                    Some(String::from_utf8_lossy(name.as_ref()).into_owned())
                }
                _ => None,
            })
            .collect()
    })
    .unwrap_or_default()
}

fn authority() -> CertAuthority {
    CertAuthority::generate(NOW).expect("generate").authority
}

fn load_error(result: Result<CertAuthority, String>) -> String {
    match result {
        Ok(_) => panic!("expected the load to fail"),
        Err(err) => err,
    }
}

#[test]
fn generated_ca_matches_the_old_template() {
    let generated = CertAuthority::generate(NOW).expect("generate");
    let authority = &generated.authority;
    let cert = authority.ca_certificate();

    let (common_name, organizations) = subject(cert);
    assert_eq!(common_name.as_deref(), Some(CA_COMMON_NAME));
    assert_eq!(organizations, vec![CA_ORGANIZATION.to_string()]);

    let constraints: BasicConstraints = extension(cert).expect("basic constraints");
    assert!(constraints.ca);
    assert_eq!(constraints.path_len_constraint, Some(1));

    let key_usage: KeyUsage = extension(cert).expect("key usage");
    assert!(key_usage.key_cert_sign());
    assert!(key_usage.crl_sign());
    assert!(!key_usage.digital_signature());

    assert!(
        extension::<SubjectKeyIdentifier>(cert).is_some(),
        "a CA carries a subject key identifier"
    );
    assert!(
        extension::<AuthorityKeyIdentifier>(cert).is_none(),
        "Go wrote no authority key identifier on the self-signed CA"
    );

    assert_eq!(
        time_to_unix(cert.tbs_certificate.validity.not_before),
        NOW - CA_VALIDITY_BEFORE_SECS
    );
    assert_eq!(
        time_to_unix(cert.tbs_certificate.validity.not_after),
        NOW + CA_VALIDITY_AFTER_SECS
    );

    // The key PEM is SEC1 with the named curve, and it matches the certificate.
    let block = pem::decode(&generated.ca_key_pem).expect("key PEM");
    assert_eq!(block.label, "EC PRIVATE KEY");
    let loaded = match CertAuthority::load(authority.ca_pem(), &generated.ca_key_pem, NOW) {
        Ok(loaded) => loaded,
        Err(err) => panic!("a freshly generated CA must load back: {err}"),
    };
    assert_eq!(loaded.ca_der(), authority.ca_der());
}

#[test]
fn issued_leaf_matches_the_old_template() {
    let authority = authority();
    let issued = authority.issue("www.example.com", NOW).expect("issue");
    let cert = certificate(&issued.chain_pem);

    let (common_name, organizations) = subject(&cert);
    assert_eq!(common_name.as_deref(), Some("www.example.com"));
    assert_eq!(organizations, vec![CA_ORGANIZATION.to_string()]);
    assert_eq!(
        cert.tbs_certificate.issuer,
        authority.ca_certificate().tbs_certificate.subject
    );

    let constraints: BasicConstraints = extension(&cert).expect("basic constraints");
    assert!(!constraints.ca);
    assert_eq!(constraints.path_len_constraint, None);

    let key_usage: KeyUsage = extension(&cert).expect("key usage");
    assert!(key_usage.digital_signature());
    assert!(!key_usage.key_cert_sign());
    assert!(!key_usage.key_encipherment());

    let eku: ExtendedKeyUsage = extension(&cert).expect("extended key usage");
    assert_eq!(eku.0, vec![ID_KP_SERVER_AUTH]);
    let eku_extension = cert
        .tbs_certificate
        .extensions
        .as_ref()
        .unwrap()
        .iter()
        .find(|extension| extension.extn_id == ExtendedKeyUsage::OID)
        .unwrap();
    assert!(
        !eku_extension.critical,
        "crypto/x509 writes a non-critical EKU"
    );

    assert_eq!(san_names(&cert), vec!["www.example.com", "*.example.com"]);

    // AKI is the CA's subject key identifier.
    let aki: AuthorityKeyIdentifier = extension(&cert).expect("authority key identifier");
    let ca_ski: SubjectKeyIdentifier =
        extension(authority.ca_certificate()).expect("CA subject key identifier");
    assert_eq!(aki.key_identifier, Some(ca_ski.0));

    assert_eq!(
        time_to_unix(cert.tbs_certificate.validity.not_before),
        NOW - LEAF_VALIDITY_BEFORE_SECS
    );
    assert_eq!(
        time_to_unix(cert.tbs_certificate.validity.not_after),
        NOW + LEAF_VALIDITY_AFTER_SECS
    );
    assert_eq!(issued.not_after_unix, NOW + LEAF_VALIDITY_AFTER_SECS);
}

#[test]
fn the_chain_holds_the_leaf_then_the_ca() {
    let authority = authority();
    let issued = authority.issue("example.com", NOW).expect("issue");
    let blocks: Vec<pem::Block> = {
        let mut rest = issued.chain_pem.as_str();
        let mut blocks = Vec::new();
        while let Some(block) = pem::decode(rest) {
            let end = rest.find("-----END CERTIFICATE-----").unwrap() + 25;
            blocks.push(block);
            rest = &rest[end..];
        }
        blocks
    };
    assert_eq!(blocks.len(), 2);
    assert_eq!(blocks[1].der, authority.ca_der());
}

#[test]
fn the_leaf_key_is_shared_and_reloads() {
    let authority = authority();
    let first = authority.issue("a.example.com", NOW).expect("issue");
    let second = authority.issue("b.example.com", NOW).expect("issue");
    assert_eq!(first.key_pem, second.key_pem);

    let first_cert = certificate(&first.chain_pem);
    let key_block = pem::decode(&first.key_pem).expect("key PEM");
    let secret = SecretKey::from_sec1_der(&key_block.der).expect("SEC1 key");
    assert_eq!(
        first_cert
            .tbs_certificate
            .subject_public_key_info
            .subject_public_key
            .raw_bytes(),
        secret.public_key().to_encoded_point(false).as_bytes()
    );

    // A leaf key is not the CA key: loading the CA with it must fail.
    assert_eq!(
        load_error(CertAuthority::load(authority.ca_pem(), &first.key_pem, NOW)),
        "CA private key does not match certificate public key"
    );
}

#[test]
fn dns_names_follow_the_old_wildcard_rule() {
    let names = |host: &str| {
        ca_dns_names(host)
            .unwrap()
            .into_iter()
            .map(|name| match name {
                GeneralName::DnsName(name) => String::from_utf8_lossy(name.as_ref()).into_owned(),
                _ => unreachable!(),
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(names("example.com"), vec!["example.com"]);
    assert_eq!(names("localhost"), vec!["localhost"]);
    assert_eq!(
        names("www.example.com"),
        vec!["www.example.com", "*.example.com"]
    );
    assert_eq!(
        names("a.b.example.com"),
        vec!["a.b.example.com", "*.b.example.com"]
    );
    assert!(ca_dns_names("例子.example").is_err());
}

#[test]
fn load_rejects_a_foreign_subject() {
    let generated = CertAuthority::generate(NOW).expect("generate");
    let cert = generated.authority.ca_certificate();
    let mut tampered = cert.clone();
    let rdns = &mut tampered.tbs_certificate.subject.0;
    rdns[1] = rdn(COMMON_NAME, "Someone Else").unwrap();
    tampered.tbs_certificate.issuer = tampered.tbs_certificate.subject.clone();
    let pem_text = pem::encode("CERTIFICATE", &tampered.to_der().unwrap());
    // The signature no longer matches, but the subject check runs first.
    let error = load_error(CertAuthority::load(&pem_text, &generated.ca_key_pem, NOW));
    assert_eq!(error, "loaded certificate has an outdated subject");
}

#[test]
fn load_checks_the_validity_window_with_injected_time() {
    let generated = CertAuthority::generate(NOW).expect("generate");
    let cert = generated.authority.ca_certificate();
    let not_after = time_to_unix(cert.tbs_certificate.validity.not_after);

    let error = load_error(CertAuthority::load(
        generated.authority.ca_pem(),
        &generated.ca_key_pem,
        not_after + 1,
    ));
    assert_eq!(
        error,
        format!(
            "CA certificate expired or not yet valid (NotBefore={}, NotAfter={})",
            ymd(NOW - CA_VALIDITY_BEFORE_SECS),
            ymd(not_after)
        )
    );
    assert!(CertAuthority::load(
        generated.authority.ca_pem(),
        &generated.ca_key_pem,
        NOW - CA_VALIDITY_BEFORE_SECS - 1
    )
    .is_err());
}

#[test]
fn load_rejects_a_mismatched_key_and_a_non_ca_certificate() {
    let first = CertAuthority::generate(NOW).expect("generate");
    let second = CertAuthority::generate(NOW).expect("generate");
    assert_eq!(
        load_error(CertAuthority::load(
            first.authority.ca_pem(),
            &second.ca_key_pem,
            NOW
        )),
        "CA private key does not match certificate public key"
    );

    let leaf = first
        .authority
        .issue("example.com", NOW)
        .expect("issue")
        .chain_pem;
    assert_eq!(
        load_error(CertAuthority::load(&leaf, &first.ca_key_pem, NOW)),
        "loaded certificate is not a CA (IsCA=false)"
    );

    assert_eq!(
        load_error(CertAuthority::load("not a pem", &first.ca_key_pem, NOW)),
        "decode CA cert PEM: no PEM block found"
    );
    assert_eq!(
        load_error(CertAuthority::load(
            first.authority.ca_pem(),
            "not a pem",
            NOW
        )),
        "decode CA key PEM: no PEM block found"
    );
}

#[test]
fn load_accepts_a_pkcs8_key() {
    let generated = CertAuthority::generate(NOW).expect("generate");
    let block = pem::decode(&generated.ca_key_pem).unwrap();
    let secret = SecretKey::from_sec1_der(&block.der).unwrap();
    let pkcs8 = pem::encode(
        "PRIVATE KEY",
        secret.to_pkcs8_der().expect("pkcs8 document").as_bytes(),
    );
    let loaded = match CertAuthority::load(generated.authority.ca_pem(), &pkcs8, NOW) {
        Ok(loaded) => loaded,
        Err(err) => panic!("{err}"),
    };
    assert_eq!(loaded.ca_der(), generated.authority.ca_der());
}

#[test]
fn the_subject_key_identifier_is_the_sha1_of_the_public_key() {
    let generated = CertAuthority::generate(NOW).expect("generate");
    let cert = generated.authority.ca_certificate();
    let ski: SubjectKeyIdentifier = extension(cert).expect("SKI");
    let spki = cert.tbs_certificate.subject_public_key_info.owned_to_ref();
    let expected = SubjectKeyIdentifier::try_from(spki).unwrap();
    assert_eq!(ski, expected);

    let has_der_extension = cert
        .tbs_certificate
        .extensions
        .as_ref()
        .unwrap()
        .iter()
        .any(|extension| extension.extn_id == ID_CE_SUBJECT_KEY_IDENTIFIER);
    assert!(has_der_extension);
}

#[test]
fn validity_helpers_round_trip_dates() {
    assert_eq!(ymd(0), "1970-01-01");
    assert_eq!(ymd(1_794_052_800), "2026-11-07");
    assert_eq!(ymd(NOW - CA_VALIDITY_BEFORE_SECS), "2026-11-06");
    let time = unix_to_time(NOW).unwrap();
    assert_eq!(time_to_unix(time), NOW);
}

#[test]
fn time_before_the_epoch_is_refused() {
    assert!(unix_to_time(-1).is_err());
    assert!(CertAuthority::generate(-10).is_err());
}
