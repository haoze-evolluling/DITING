//! Replays the fixtures generated from the pre-migration Go implementation
//! (`android/engine/zz_cert_fixture_gen_test.go` before it was deleted):
//!
//! * `legacy_ca.crt` / `legacy_ca.key` - a root CA written by the old `generateCA` + `saveCA`, which
//!   the kernel must still load (upgrade path: an APK that updates must not invalidate the CA the
//!   user already installed);
//! * `legacy_ca_info.tsv` - the subject, validity window, serial and SKI the old code produced, plus
//!   the SAN list it minted for four hosts;
//! * `ev.tsv` - `isExtendedValidation` over the policy lists the old code saw.
//!
//! The fixture CA lives from 2026-11-06 to 2036-11-04; the replay pins `now` one day before its
//! `NotAfter` so the test does not expire with it.

use std::collections::HashMap;
use std::fs;

use const_oid::AssociatedOid;
use der::Decode;
use diting_cert_core::ca::{
    dns_names, subject, time_to_unix, CertAuthority, CA_ORGANIZATION, LEAF_VALIDITY_AFTER_SECS,
};
use diting_cert_core::ev::is_extended_validation_csv;
use diting_cert_core::pem;
use x509_cert::ext::pkix::name::GeneralName;
use x509_cert::Certificate;

fn fixtures() -> String {
    format!("{}/tests/fixtures", env!("CARGO_MANIFEST_DIR"))
}

fn read(name: &str) -> String {
    let path = format!("{}/{name}", fixtures());
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("{path}: {err}"))
}

fn info() -> HashMap<String, String> {
    read("legacy_ca_info.tsv")
        .lines()
        .filter(|line| !line.is_empty())
        .filter_map(|line| {
            let (key, value) = line.split_once('\t')?;
            Some((key.to_string(), value.to_string()))
        })
        .collect()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn leaf_certificate(chain_pem: &str) -> Certificate {
    let block = pem::decode(chain_pem).expect("leaf PEM");
    Certificate::from_der(&block.der).expect("leaf DER")
}

fn dns_of(cert: &Certificate) -> Vec<String> {
    let extensions = cert
        .tbs_certificate
        .extensions
        .as_ref()
        .expect("extensions");
    let san = extensions
        .iter()
        .find(|extension| extension.extn_id == x509_cert::ext::pkix::SubjectAltName::OID)
        .expect("SAN");
    let san: x509_cert::ext::pkix::SubjectAltName =
        der::Decode::from_der(san.extn_value.as_bytes()).expect("SAN value");
    san.0
        .iter()
        .map(|name| match name {
            GeneralName::DnsName(name) => String::from_utf8_lossy(name.as_ref()).into_owned(),
            other => panic!("unexpected SAN entry {other:?}"),
        })
        .collect()
}

#[test]
fn the_legacy_ca_still_loads() {
    let info = info();
    let not_after: i64 = info["ca_not_after"].parse().unwrap();
    let pinned_now = not_after - 86_400;

    let authority = CertAuthority::load(&read("legacy_ca.crt"), &read("legacy_ca.key"), pinned_now)
        .expect("the CA the old code wrote must load");

    let cert = authority.ca_certificate();
    let (common_name, organizations) = subject(cert);
    assert_eq!(organizations, vec![CA_ORGANIZATION.to_string()]);
    assert!(common_name.is_some());
    assert!(common_name
        .unwrap()
        .contains("DITING HTTPS Inspection Root CA"));

    assert_eq!(
        time_to_unix(cert.tbs_certificate.validity.not_before),
        info["ca_not_before"].parse::<i64>().unwrap()
    );
    assert_eq!(
        time_to_unix(cert.tbs_certificate.validity.not_after),
        not_after
    );

    // The old PEM is returned byte for byte, so `GetCACertPEM` keeps handing the installed CA out.
    assert_eq!(authority.ca_pem(), read("legacy_ca.crt"));

    let ski = {
        let extensions = cert.tbs_certificate.extensions.as_ref().unwrap();
        let extension = extensions
            .iter()
            .find(|extension| extension.extn_id == x509_cert::ext::pkix::SubjectKeyIdentifier::OID)
            .expect("SKI");
        let ski: x509_cert::ext::pkix::SubjectKeyIdentifier =
            der::Decode::from_der(extension.extn_value.as_bytes()).expect("SKI value");
        hex(ski.0.as_bytes())
    };
    assert_eq!(ski, info["ca_ski"]);
    assert_eq!(
        hex(cert.tbs_certificate.serial_number.as_bytes()),
        info["ca_serial"]
    );
}

#[test]
fn leaves_from_the_legacy_ca_carry_the_old_sans() {
    let info = info();
    let pinned_now: i64 = info["ca_not_after"].parse::<i64>().unwrap() - 86_400;
    let authority = CertAuthority::load(&read("legacy_ca.crt"), &read("legacy_ca.key"), pinned_now)
        .expect("load");

    let mut checked = 0;
    for (key, value) in &info {
        let Some(host) = key.strip_prefix("san.") else {
            continue;
        };
        let mut fields = value.split('\t');
        let expected_cn = fields.next().unwrap();
        let expected_names: Vec<&str> = fields.next().unwrap().split(',').collect();

        let issued = authority.issue(host, pinned_now).expect("issue");
        let cert = leaf_certificate(&issued.chain_pem);
        let (common_name, organizations) = subject(&cert);
        assert_eq!(common_name.as_deref(), Some(expected_cn));
        assert_eq!(organizations, vec![CA_ORGANIZATION.to_string()]);
        assert_eq!(dns_of(&cert), expected_names, "SAN of {host}");
        assert_eq!(issued.not_after_unix, pinned_now + LEAF_VALIDITY_AFTER_SECS);

        // What the kernel's own SAN helper says must agree with the certificate it wrote.
        let helper: Vec<String> = dns_names(host)
            .unwrap()
            .into_iter()
            .map(|name| match name {
                GeneralName::DnsName(name) => String::from_utf8_lossy(name.as_ref()).into_owned(),
                _ => unreachable!(),
            })
            .collect();
        assert_eq!(helper, expected_names);
        checked += 1;
    }
    assert_eq!(checked, 4);
}

#[test]
fn ev_corpus_matches_the_old_predicate() {
    let body = read("ev.tsv");
    let mut checked = 0;
    for line in body.lines().filter(|line| !line.is_empty()) {
        let mut fields = line.split('\t');
        let name = fields.next().unwrap();
        let csv = fields.next().unwrap_or("");
        let expected = fields.next().unwrap_or("false") == "true";
        assert_eq!(
            is_extended_validation_csv(csv),
            expected,
            "{name} ({csv:?})"
        );
        checked += 1;
    }
    assert!(checked >= 17, "only {checked} EV rows");
}
