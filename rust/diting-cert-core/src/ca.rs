//! The root CA and the per-host leaf certificates.
//!
//! Everything the old `mitm_cert_manager.go` did with `crypto/x509` happens here, with the same
//! profile:
//!
//! * root CA: P-256, self-signed, subject `O=DITING, CN=DITING HTTPS Inspection Root CA`, valid
//!   from `now - 24h` to `now + 10 * 365d`, `KeyUsage = certSign | cRLSign`, `CA:TRUE,
//!   pathlen:1`, and a subject key identifier (SHA-1 of the public key). Go wrote no authority key
//!   identifier on the self-signed CA, so neither do we.
//! * leaf: subject `O=DITING, CN=<host>`, valid from `now - 1h` to `now + 24h`,
//!   `KeyUsage = digitalSignature`, `EKU = serverAuth` (non-critical, like `crypto/x509`),
//!   `CA:FALSE`, the CA's key identifier as its AKI, and a SAN list holding `<host>` plus
//!   `*.<rest>` when the part after the first label still contains a dot (the old rule, quirks
//!   included: `example.com` gets no wildcard, `www.example.com` gets `*.example.com`).
//! * one shared P-256 leaf key per handle, exactly like the old `sharedLeafKey`.
//!
//! Private keys are SEC1 `EC PRIVATE KEY` with the named-curve parameters, because that is what
//! `x509.MarshalECPrivateKey` wrote and what `x509.ParseECPrivateKey` (and therefore an older APK)
//! reads. Loading also accepts PKCS#8, which the Go side never wrote but costs nothing to allow.
//!
//! Nothing here reads a clock: every entry point takes `now_unix` seconds.

use const_oid::db::rfc4519::{COMMON_NAME, ORGANIZATION_NAME};
use const_oid::db::rfc5280::{ID_CE_BASIC_CONSTRAINTS, ID_KP_SERVER_AUTH};
use const_oid::db::rfc5912::ID_EC_PUBLIC_KEY;
use const_oid::{AssociatedOid, ObjectIdentifier};
use der::asn1::{Ia5String, PrintableStringRef, Utf8StringRef};
use der::referenced::OwnedToRef;
use der::{Any, Decode, Encode, Length, Writer};
use ecdsa::der::Signature as DerSignature;
use p256::ecdsa::SigningKey;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use p256::pkcs8::DecodePrivateKey;
use p256::{NistP256, SecretKey};
use rand_core::{OsRng, RngCore};
use sec1::{EcParameters, EcPrivateKey};
use x509_cert::attr::AttributeTypeAndValue;
use x509_cert::builder::{Builder, CertificateBuilder, Profile};
use x509_cert::ext::pkix::name::{GeneralName, GeneralNames};
use x509_cert::ext::pkix::{
    AuthorityKeyIdentifier, BasicConstraints, ExtendedKeyUsage, KeyUsage, KeyUsages,
    SubjectAltName, SubjectKeyIdentifier,
};
use x509_cert::ext::{AsExtension, Extension};
use x509_cert::name::{Name, RdnSequence, RelativeDistinguishedName};
use x509_cert::serial_number::SerialNumber;
use x509_cert::spki::SubjectPublicKeyInfoOwned;
use x509_cert::time::{Time, Validity};
use x509_cert::Certificate;

use crate::pem;

/// `caOrganization` in the old Go file.
pub const CA_ORGANIZATION: &str = "DITING";
/// `caCommonName` in the old Go file.
pub const CA_COMMON_NAME: &str = "DITING HTTPS Inspection Root CA";
/// `time.Now().Add(-24 * time.Hour)` on the CA template.
pub const CA_VALIDITY_BEFORE_SECS: i64 = 24 * 60 * 60;
/// `time.Now().Add(10 * 365 * 24 * time.Hour)` on the CA template.
pub const CA_VALIDITY_AFTER_SECS: i64 = 10 * 365 * 24 * 60 * 60;
/// `time.Now().Add(-1 * time.Hour)` on the leaf template.
pub const LEAF_VALIDITY_BEFORE_SECS: i64 = 60 * 60;
/// `time.Now().Add(24 * time.Hour)` on the leaf template.
pub const LEAF_VALIDITY_AFTER_SECS: i64 = 24 * 60 * 60;

/// The root CA plus the shared leaf key of one engine.
pub struct CertAuthority {
    ca_cert: Certificate,
    ca_cert_der: Vec<u8>,
    ca_cert_pem: String,
    ca_subject: Name,
    ca_spki: SubjectPublicKeyInfoOwned,
    ca_signing: SigningKey,
    leaf_secret: SecretKey,
}

/// A freshly generated CA and the SEC1 PEM the caller has to persist.
pub struct GeneratedCa {
    pub authority: CertAuthority,
    pub ca_key_pem: String,
}

/// One minted leaf certificate.
pub struct IssuedLeaf {
    /// Leaf certificate PEM followed by the CA certificate PEM (`tls.X509KeyPair` input).
    pub chain_pem: String,
    /// The shared leaf key as SEC1 PEM.
    pub key_pem: String,
    /// The leaf's `NotAfter`, so the caller's cache expires it at the same instant.
    pub not_after_unix: i64,
}

impl CertAuthority {
    /// `generateCA`: a fresh P-256 root with a new leaf key.
    pub fn generate(now_unix: i64) -> Result<GeneratedCa, String> {
        let ca_secret = SecretKey::random(&mut OsRng);
        let ca_signing = SigningKey::from(&ca_secret);
        let ca_spki = SubjectPublicKeyInfoOwned::from_key(*ca_signing.verifying_key())
            .map_err(|err| format!("create CA cert: {err}"))?;

        let mut builder = CertificateBuilder::new(
            Profile::Manual { issuer: None },
            random_serial()?,
            validity(
                now_unix,
                CA_VALIDITY_BEFORE_SECS,
                CA_VALIDITY_AFTER_SECS,
                "create CA cert",
            )?,
            name(CA_COMMON_NAME)?,
            ca_spki.clone(),
            &ca_signing,
        )
        .map_err(|err| format!("create CA cert: {err}"))?;
        let subject_key_id = SubjectKeyIdentifier::try_from(ca_spki.owned_to_ref())
            .map_err(|err| format!("create CA cert: {err}"))?;
        builder
            .add_extension(&subject_key_id)
            .map_err(|err| format!("create CA cert: {err}"))?;
        builder
            .add_extension(&BasicConstraints {
                ca: true,
                path_len_constraint: Some(1),
            })
            .map_err(|err| format!("create CA cert: {err}"))?;
        builder
            .add_extension(&KeyUsage(KeyUsages::KeyCertSign | KeyUsages::CRLSign))
            .map_err(|err| format!("create CA cert: {err}"))?;
        let ca_cert = builder
            .build::<DerSignature<NistP256>>()
            .map_err(|err| format!("create CA cert: {err}"))?;

        let ca_key_pem = sec1_pem(&ca_secret)?;
        let authority =
            CertAuthority::new(ca_cert, ca_signing, ca_spki, SecretKey::random(&mut OsRng))?;
        Ok(GeneratedCa {
            authority,
            ca_key_pem,
        })
    }

    /// `loadCA`: parse and validate a persisted root.
    pub fn load(cert_pem: &str, key_pem: &str, now_unix: i64) -> Result<Self, String> {
        let cert_block = pem::decode(cert_pem)
            .ok_or_else(|| "decode CA cert PEM: no PEM block found".to_string())?;
        let ca_cert = Certificate::from_der(&cert_block.der)
            .map_err(|err| format!("parse CA cert: {err}"))?;

        if !is_ca(&ca_cert) {
            return Err("loaded certificate is not a CA (IsCA=false)".to_string());
        }
        let (common_name, organizations) = subject(&ca_cert);
        if common_name.as_deref() != Some(CA_COMMON_NAME)
            || organizations != [CA_ORGANIZATION.to_string()]
        {
            return Err("loaded certificate has an outdated subject".to_string());
        }
        let not_before = time_to_unix(ca_cert.tbs_certificate.validity.not_before);
        let not_after = time_to_unix(ca_cert.tbs_certificate.validity.not_after);
        if now_unix < not_before || now_unix > not_after {
            return Err(format!(
                "CA certificate expired or not yet valid (NotBefore={}, NotAfter={})",
                ymd(not_before),
                ymd(not_after)
            ));
        }

        let key_block = pem::decode(key_pem)
            .ok_or_else(|| "decode CA key PEM: no PEM block found".to_string())?;
        let ca_secret = SecretKey::from_sec1_der(&key_block.der)
            .or_else(|_| SecretKey::from_pkcs8_der(&key_block.der))
            .map_err(|err| format!("parse CA key: {err}"))?;
        if ca_cert
            .tbs_certificate
            .subject_public_key_info
            .algorithm
            .oid
            != ID_EC_PUBLIC_KEY
        {
            return Err("CA certificate public key is not ECDSA".to_string());
        }
        let derived = ca_secret.public_key().to_encoded_point(false);
        if ca_cert
            .tbs_certificate
            .subject_public_key_info
            .subject_public_key
            .raw_bytes()
            != derived.as_bytes()
        {
            return Err("CA private key does not match certificate public key".to_string());
        }

        let ca_signing = SigningKey::from(&ca_secret);
        let ca_spki = ca_cert.tbs_certificate.subject_public_key_info.clone();
        CertAuthority::new(ca_cert, ca_signing, ca_spki, SecretKey::random(&mut OsRng))
    }

    /// `getCertForHost`: one leaf for `host`, valid around `now_unix`.
    pub fn issue(&self, host: &str, now_unix: i64) -> Result<IssuedLeaf, String> {
        let not_after_unix = now_unix
            .checked_add(LEAF_VALIDITY_AFTER_SECS)
            .ok_or_else(|| format!("sign leaf cert for {host}: time overflows"))?;
        let leaf_spki = SubjectPublicKeyInfoOwned::from_key(
            *SigningKey::from(&self.leaf_secret).verifying_key(),
        )
        .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        let dns_names =
            dns_names(host).map_err(|err| format!("sign leaf cert for {host}: {err}"))?;

        let mut builder = CertificateBuilder::new(
            Profile::Manual {
                issuer: Some(self.ca_subject.clone()),
            },
            random_serial().map_err(|err| format!("generate serial for {host}: {err}"))?,
            validity(
                now_unix,
                LEAF_VALIDITY_BEFORE_SECS,
                LEAF_VALIDITY_AFTER_SECS,
                "sign leaf cert",
            )?,
            name(host)?,
            leaf_spki,
            &self.ca_signing,
        )
        .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;

        let key_identifier = SubjectKeyIdentifier::try_from(self.ca_spki.owned_to_ref())
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&AuthorityKeyIdentifier {
                key_identifier: Some(key_identifier.0),
                ..Default::default()
            })
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&BasicConstraints {
                ca: false,
                path_len_constraint: None,
            })
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&KeyUsage(KeyUsages::DigitalSignature.into()))
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&NonCriticalExtendedKeyUsage(ExtendedKeyUsage(vec![
                ID_KP_SERVER_AUTH,
            ])))
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&SubjectAltName(dns_names))
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;

        let leaf = builder
            .build::<DerSignature<NistP256>>()
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        let leaf_der = leaf
            .to_der()
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        let mut chain_pem = pem::encode("CERTIFICATE", &leaf_der);
        chain_pem.push_str(&self.ca_cert_pem);
        Ok(IssuedLeaf {
            chain_pem,
            key_pem: sec1_pem(&self.leaf_secret)?,
            not_after_unix,
        })
    }

    /// `GetCACertPEM`.
    pub fn ca_pem(&self) -> &str {
        &self.ca_cert_pem
    }

    /// The CA certificate in DER (tests and diagnostics).
    pub fn ca_der(&self) -> &[u8] {
        &self.ca_cert_der
    }

    /// The parsed CA certificate (tests and diagnostics).
    pub fn ca_certificate(&self) -> &Certificate {
        &self.ca_cert
    }

    fn new(
        ca_cert: Certificate,
        ca_signing: SigningKey,
        ca_spki: SubjectPublicKeyInfoOwned,
        leaf_secret: SecretKey,
    ) -> Result<Self, String> {
        let ca_cert_der = ca_cert
            .to_der()
            .map_err(|err| format!("encode CA cert: {err}"))?;
        let ca_cert_pem = pem::encode("CERTIFICATE", &ca_cert_der);
        let ca_subject = ca_cert.tbs_certificate.subject.clone();
        Ok(CertAuthority {
            ca_cert,
            ca_cert_der,
            ca_cert_pem,
            ca_subject,
            ca_spki,
            ca_signing,
            leaf_secret,
        })
    }
}

/// The `DNSNames` the old code built: the host, plus `*.<rest>` when `rest` has another dot.
pub fn dns_names(host: &str) -> Result<GeneralNames, String> {
    let mut names = Vec::with_capacity(2);
    names.push(GeneralName::DnsName(Ia5String::new(host).map_err(
        |_| format!("{host:?} cannot be encoded as an IA5String"),
    )?));
    if let Some((_, rest)) = host.split_once('.') {
        if rest.contains('.') {
            let wildcard = format!("*.{rest}");
            names.push(GeneralName::DnsName(Ia5String::new(&wildcard).map_err(
                |_| format!("{wildcard:?} cannot be encoded as an IA5String"),
            )?));
        }
    }
    Ok(names)
}

/// `EKU = serverAuth` marked non-critical, which is what `crypto/x509` writes.
struct NonCriticalExtendedKeyUsage(ExtendedKeyUsage);

impl AssociatedOid for NonCriticalExtendedKeyUsage {
    const OID: ObjectIdentifier = ExtendedKeyUsage::OID;
}

impl AsExtension for NonCriticalExtendedKeyUsage {
    fn critical(&self, _subject: &Name, _extensions: &[Extension]) -> bool {
        false
    }
}

impl Encode for NonCriticalExtendedKeyUsage {
    fn encoded_len(&self) -> der::Result<Length> {
        self.0.encoded_len()
    }

    fn encode(&self, writer: &mut impl Writer) -> der::Result<()> {
        self.0.encode(writer)
    }
}

fn random_serial() -> Result<SerialNumber, String> {
    let mut bytes = [0u8; 16];
    OsRng.fill_bytes(&mut bytes);
    // Positive, non-zero, at most 128 bits: the same shape `rand.Int(1 << 128)` produced.
    bytes[0] = (bytes[0] & 0x7f) | 0x01;
    SerialNumber::new(&bytes).map_err(|err| format!("generate serial: {err}"))
}

fn validity(
    now_unix: i64,
    before_secs: i64,
    after_secs: i64,
    context: &str,
) -> Result<Validity, String> {
    Ok(Validity {
        not_before: unix_to_time(now_unix - before_secs)
            .map_err(|err| format!("{context}: {err}"))?,
        not_after: unix_to_time(now_unix + after_secs)
            .map_err(|err| format!("{context}: {err}"))?,
    })
}

fn unix_to_time(unix: i64) -> Result<Time, String> {
    let seconds = u64::try_from(unix).map_err(|_| "validity before the unix epoch".to_string())?;
    Time::try_from(std::time::UNIX_EPOCH + std::time::Duration::from_secs(seconds))
        .map_err(|err| format!("encode validity time: {err}"))
}

fn name(common_name: &str) -> Result<Name, String> {
    Ok(RdnSequence(vec![
        rdn(ORGANIZATION_NAME, CA_ORGANIZATION)?,
        rdn(COMMON_NAME, common_name)?,
    ]))
}

fn rdn(oid: ObjectIdentifier, value: &str) -> Result<RelativeDistinguishedName, String> {
    // `crypto/x509` writes PrintableString when it can and UTF8String otherwise.
    let any = match PrintableStringRef::new(value) {
        Ok(printable) => Any::from(printable),
        Err(_) => Any::from(
            Utf8StringRef::new(value)
                .map_err(|_| format!("{value:?} cannot be encoded as a name"))?,
        ),
    };
    RelativeDistinguishedName::try_from(vec![AttributeTypeAndValue { oid, value: any }])
        .map_err(|err| format!("build name for {value:?}: {err}"))
}

fn sec1_pem(secret: &SecretKey) -> Result<String, String> {
    let private_key = secret.to_bytes();
    let public_key = secret.public_key().to_encoded_point(false);
    let key = EcPrivateKey {
        private_key: &private_key,
        parameters: Some(EcParameters::NamedCurve(NistP256::OID)),
        public_key: Some(public_key.as_bytes()),
    };
    let der = key
        .to_der()
        .map_err(|err| format!("encode private key: {err}"))?;
    Ok(pem::encode("EC PRIVATE KEY", &der))
}

fn is_ca(cert: &Certificate) -> bool {
    let Some(extensions) = &cert.tbs_certificate.extensions else {
        return false;
    };
    extensions
        .iter()
        .find(|extension| extension.extn_id == ID_CE_BASIC_CONSTRAINTS)
        .and_then(|extension| BasicConstraints::from_der(extension.extn_value.as_bytes()).ok())
        .map(|constraints| constraints.ca)
        .unwrap_or(false)
}

/// The `CommonName` and every `Organization` of the subject.
pub fn subject(cert: &Certificate) -> (Option<String>, Vec<String>) {
    let mut common_name = None;
    let mut organizations = Vec::new();
    for rdn in &cert.tbs_certificate.subject.0 {
        for attribute in rdn.0.iter() {
            let text = String::from_utf8_lossy(attribute.value.value()).into_owned();
            if attribute.oid == COMMON_NAME {
                common_name = Some(text);
            } else if attribute.oid == ORGANIZATION_NAME {
                organizations.push(text);
            }
        }
    }
    (common_name, organizations)
}

/// `Time` to unix seconds without the pre-epoch panic in `to_unix_duration`.
pub fn time_to_unix(time: Time) -> i64 {
    let date = time.to_date_time();
    let days = days_from_civil(date.year().into(), date.month(), date.day());
    days * 86_400
        + i64::from(date.hour()) * 3_600
        + i64::from(date.minutes()) * 60
        + i64::from(date.seconds())
}

/// Howard Hinnant's `days_from_civil`: days since 1970-01-01 for a proleptic Gregorian date.
fn days_from_civil(year: i64, month: u8, day: u8) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let month = i64::from(month);
    let month_shifted = if month > 2 { month - 3 } else { month + 9 };
    let day_of_year = (153 * month_shifted + 2) / 5 + i64::from(day) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

/// `YYYY-MM-DD` for the load error message (`time.Format("2006-01-02")`).
pub fn ymd(unix: i64) -> String {
    let days = unix.div_euclid(86_400);
    let shifted = days + 719_468;
    let era = if shifted >= 0 {
        shifted
    } else {
        shifted - 146_096
    } / 146_097;
    let day_of_era = shifted - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let mut year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_position = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_position + 2) / 5 + 1;
    let month = if month_position < 10 {
        month_position + 3
    } else {
        month_position - 9
    };
    if month <= 2 {
        year += 1;
    }
    format!("{year:04}-{month:02}-{day:02}")
}

#[cfg(test)]
mod tests;
